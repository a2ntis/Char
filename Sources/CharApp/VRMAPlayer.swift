import Foundation
import RealityKit
import VRMRealityKit

struct CompanionVRMAOption: Identifiable, Hashable {
    let id: String
    let displayName: String
    let filePath: String
}

struct CompanionPoseOption: Identifiable, Hashable {
    let id: String
    let displayName: String
    let filePath: String
}

enum PoseCatalog {
    static func discover(in assetsRoot: URL) -> [CompanionPoseOption] {
        let folder = assetsRoot.appendingPathComponent("Poses", isDirectory: true)
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        return enumerator
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension.lowercased() == "vroidpose" }
            .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
            .map {
                CompanionPoseOption(
                    id: $0.path,
                    displayName: prettifyName($0.deletingPathExtension().lastPathComponent),
                    filePath: $0.path
                )
            }
    }

    private static func prettifyName(_ rawName: String) -> String {
        rawName
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum VRMACatalog {
    static func discover(in assetsRoot: URL) -> [CompanionVRMAOption] {
        let folder = assetsRoot.appendingPathComponent("VRMA", isDirectory: true)
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        let files = enumerator
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension.lowercased() == "vrma" }
            .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
            .map {
                CompanionVRMAOption(
                    id: $0.path,
                    displayName: prettifyName($0.deletingPathExtension().lastPathComponent),
                    filePath: $0.path
                )
            }

        return files
    }

    private static func prettifyName(_ rawName: String) -> String {
        let withoutPrefix = rawName.replacingOccurrences(of: #"^\d+[_\-\s]*"#, with: "", options: .regularExpression)
        let withSpaces = withoutPrefix
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
        return withSpaces.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum VRMCoordinateConvention {
    case v0
    case v1
}

enum VRMAPlayerError: Error {
    case invalidHeader
    case invalidJSONChunk
    case missingBinaryChunk
    case unsupportedAccessor
    case missingAnimation
}

// MARK: - GLB / glTF structures

private struct VRMAGLTF: Decodable {
    struct BufferView: Decodable {
        let buffer: Int
        let byteOffset: Int?
        let byteLength: Int
        let byteStride: Int?
    }

    struct Accessor: Decodable {
        let bufferView: Int?
        let byteOffset: Int?
        let componentType: Int
        let count: Int
        let type: String
    }

    struct Node: Decodable {
        let name: String?
        let rotation: [Float]?
        let translation: [Float]?
    }

    struct Animation: Decodable {
        struct Sampler: Decodable {
            let input: Int
            let output: Int
            let interpolation: String?
        }

        struct Channel: Decodable {
            struct Target: Decodable {
                let node: Int
                let path: String
            }

            let sampler: Int
            let target: Target
        }

        let samplers: [Sampler]
        let channels: [Channel]
    }

    struct Extensions: Decodable {
        struct VRMCAnimation: Decodable {
            let specVersion: String?
            struct Humanoid: Decodable {
                struct BoneRef: Decodable {
                    let node: Int
                }
                let humanBones: [String: BoneRef]?
            }
            let humanoid: Humanoid?
        }

        // swiftlint:disable:next identifier_name
        let VRMC_vrm_animation: VRMCAnimation?
    }

    let bufferViews: [BufferView]
    let accessors: [Accessor]
    let nodes: [Node]?
    let animations: [Animation]?
    let extensions: Extensions?
}

// MARK: - Parsed clip data

private enum VRMAChannelValue {
    case translation([SIMD3<Float>])
    case rotation([simd_quatf])
}

private struct VRMAChannel {
    let boneName: String
    let times: [Float]
    let values: VRMAChannelValue
    let sourceRestRotation: simd_quatf
}

private struct VRMAClip {
    let duration: Float
    let channels: [VRMAChannel]
    let sourceHipsRestPosition: SIMD3<Float>
}

// MARK: - VRMAPlayer

@MainActor
final class VRMAPlayer {
    private let clip: VRMAClip
    private weak var vrmEntity: VRMEntity?
    private let convention: VRMCoordinateConvention

    private var currentTime: Float = 0

    private var boneRestTransforms: [Humanoid.Bones: Transform]
    private var chestEntity: Entity?
    private var chestRestTransform: Transform?

    private let blendInDuration: Float = 0.25
    private let blendOutDuration: Float = 0.35
    private var restGroundY: Float?

    private static let faceBoneNames: Set<String> = [
        "leftEye", "rightEye", "jaw",
    ]

    init(
        filePath: String,
        vrmEntity: VRMEntity,
        restTransforms: [Humanoid.Bones: Transform],
        chestEntity: Entity?,
        chestRestTransform: Transform?,
        convention: VRMCoordinateConvention = .v0
    ) throws {
        self.clip = try Self.loadClip(filePath: filePath)
        self.vrmEntity = vrmEntity
        self.boneRestTransforms = restTransforms
        self.chestEntity = chestEntity
        self.chestRestTransform = chestRestTransform
        self.convention = convention
    }

    var duration: Float { clip.duration }

    func reset() {
        currentTime = 0
    }

    func update(deltaTime: TimeInterval) -> Bool {
        guard let vrmEntity else { return false }

        if restGroundY == nil {
            let leftFootY = vrmEntity.humanoid.node(for: .leftFoot)?.position(relativeTo: vrmEntity.entity).y
            let rightFootY = vrmEntity.humanoid.node(for: .rightFoot)?.position(relativeTo: vrmEntity.entity).y
            switch (leftFootY, rightFootY) {
            case let (ly?, ry?): restGroundY = min(ly, ry)
            case let (ly?, nil): restGroundY = ly
            case let (nil, ry?): restGroundY = ry
            default: break
            }
        }

        currentTime += Float(deltaTime)
        let clampedTime = min(currentTime, clip.duration)

        let blendWeight = computeBlendWeight(at: clampedTime)

        var boneStates: [String: (translation: SIMD3<Float>?, rotation: simd_quatf?, sourceRest: simd_quatf)] = [:]

        for channel in clip.channels {
            if Self.faceBoneNames.contains(channel.boneName) { continue }

            let (lower, upper, t) = sampleSegment(for: clampedTime, in: channel.times)
            var entry = boneStates[channel.boneName] ?? (nil, nil, channel.sourceRestRotation)

            switch channel.values {
            case .translation(let values):
                let a = values[lower]
                let b = values[upper]
                entry.translation = simd_mix(a, b, SIMD3<Float>(repeating: t))
            case .rotation(let values):
                let a = values[lower]
                let b = values[upper]
                entry.rotation = simd_slerp(a, b, t)
            }
            boneStates[channel.boneName] = entry
        }

        for (boneName, state) in boneStates {
            if boneName == "chest" {
                applyChest(state: state, blendWeight: blendWeight)
                continue
            }

            guard let bone = Self.humanoidBone(for: boneName),
                  let entity = vrmEntity.humanoid.node(for: bone) else { continue }

            let restTransform = boneRestTransforms[bone] ?? entity.transform

            if let clipRotation = state.rotation {
                let retargeted = retargetRotation(
                    clipRotation: clipRotation,
                    sourceRest: state.sourceRest,
                    targetRest: restTransform.rotation
                )
                entity.transform.rotation = simd_slerp(restTransform.rotation, retargeted, blendWeight)
            }

            if bone == .hips, let clipTranslation = state.translation {
                let sourceRestY = clip.sourceHipsRestPosition.y
                let targetRestY = restTransform.translation.y
                let heightRatio: Float = sourceRestY > 0.001 ? targetRestY / sourceRestY : 1.0
                let deltaY = (clipTranslation.y - sourceRestY) * heightRatio
                var pos = restTransform.translation
                pos.y += deltaY * blendWeight
                entity.transform.translation = pos
            }
        }

        applyFootGrounding(on: vrmEntity, blendWeight: blendWeight)

        let finished = currentTime >= clip.duration
        if finished {
            restoreAll(on: vrmEntity)
        }
        return !finished
    }

    func restoreAll(on vrmEntity: VRMEntity) {
        for (bone, rest) in boneRestTransforms {
            vrmEntity.humanoid.node(for: bone)?.transform = rest
        }
        if let chestEntity, let chestRest = chestRestTransform {
            chestEntity.transform = chestRest
        }
    }

    // MARK: - Foot grounding

    /// After applying all VRMA bone transforms, check if the lowest foot is above
    /// its rest-pose ground level. If so, push hips down to plant feet on the ground.
    /// This compensates for limb length differences between the source VRMA skeleton
    /// and the target VRM model.
    private func applyFootGrounding(on vrmEntity: VRMEntity, blendWeight: Float) {
        guard blendWeight > 0.001, let groundY = restGroundY else { return }

        let leftFootY = vrmEntity.humanoid.node(for: .leftFoot)?.position(relativeTo: vrmEntity.entity).y
        let rightFootY = vrmEntity.humanoid.node(for: .rightFoot)?.position(relativeTo: vrmEntity.entity).y

        let lowestFootY: Float
        switch (leftFootY, rightFootY) {
        case let (ly?, ry?): lowestFootY = min(ly, ry)
        case let (ly?, nil): lowestFootY = ly
        case let (nil, ry?): lowestFootY = ry
        default: return
        }

        let drift = lowestFootY - groundY
        let maxCorrection: Float = 0.15
        guard drift > 0.002 else { return }

        let correction = min(drift, maxCorrection)
        if let hipsEntity = vrmEntity.humanoid.node(for: .hips) {
            hipsEntity.transform.translation.y -= correction
        }
    }

    // MARK: - Retargeting

    /// VRMA uses VRM 1.0 bone convention (+Z forward, left arm along +X).
    /// VRM 0.x from Unity uses the opposite (-Z forward, left arm along -X).
    /// Conjugation by πY converts between the two: negate X and Z quaternion components.
    private static func vrm10toVRM0x(_ q: simd_quatf) -> simd_quatf {
        simd_quatf(ix: -q.imag.x, iy: q.imag.y, iz: -q.imag.z, r: q.real)
    }

    private func retargetRotation(
        clipRotation: simd_quatf,
        sourceRest: simd_quatf,
        targetRest: simd_quatf
    ) -> simd_quatf {
        let normalized = simd_normalize(sourceRest.inverse * clipRotation)
        let corrected: simd_quatf
        switch convention {
        case .v0:
            corrected = Self.vrm10toVRM0x(normalized)
        case .v1:
            corrected = normalized
        }
        return simd_normalize(targetRest * corrected)
    }

    // MARK: - Chest (not in Humanoid.Bones)

    private func applyChest(
        state: (translation: SIMD3<Float>?, rotation: simd_quatf?, sourceRest: simd_quatf),
        blendWeight: Float
    ) {
        guard let chestEntity, let chestRest = chestRestTransform else { return }
        if let clipRotation = state.rotation {
            let retargeted = retargetRotation(
                clipRotation: clipRotation,
                sourceRest: state.sourceRest,
                targetRest: chestRest.rotation
            )
            chestEntity.transform.rotation = simd_slerp(chestRest.rotation, retargeted, blendWeight)
        }
    }

    // MARK: - Blend weight

    private func computeBlendWeight(at t: Float) -> Float {
        let fadeIn = blendInDuration > 0 ? min(1, t / blendInDuration) : 1
        let remaining = clip.duration - t
        let fadeOut = blendOutDuration > 0 ? min(1, remaining / blendOutDuration) : 1
        return max(0, min(fadeIn, fadeOut))
    }

    // MARK: - Sampling

    private func sampleSegment(for time: Float, in times: [Float]) -> (lower: Int, upper: Int, t: Float) {
        guard !times.isEmpty else { return (0, 0, 0) }
        if time <= times[0] { return (0, 0, 0) }
        for index in 1..<times.count {
            if time <= times[index] {
                let start = times[index - 1]
                let end = times[index]
                let t = end > start ? (time - start) / (end - start) : 0
                return (index - 1, index, t)
            }
        }
        let last = times.count - 1
        return (last, last, 0)
    }

    // MARK: - Bone name → Humanoid.Bones

    private static func humanoidBone(for name: String) -> Humanoid.Bones? {
        if name == "chest" { return nil }
        return Humanoid.Bones(rawValue: name)
    }

    // MARK: - GLB parsing

    private static func loadClip(filePath: String) throws -> VRMAClip {
        let fileData = try Data(contentsOf: URL(fileURLWithPath: filePath))
        let (jsonData, binaryData) = try splitGLB(fileData)
        let gltf = try JSONDecoder().decode(VRMAGLTF.self, from: jsonData)
        guard let animation = gltf.animations?.first else {
            throw VRMAPlayerError.missingAnimation
        }

        let boneMapping = buildBoneMapping(gltf: gltf)

        var channels: [VRMAChannel] = []
        var maxTime: Float = 0
        var hipsRestPosition = SIMD3<Float>(0, 0.9, 0)

        for channel in animation.channels {
            guard channel.sampler < animation.samplers.count,
                  channel.target.node < (gltf.nodes?.count ?? 0) else { continue }

            let nodeIndex = channel.target.node
            guard let boneName = boneMapping[nodeIndex] else { continue }

            let sampler = animation.samplers[channel.sampler]
            let times = try readScalars(accessorIndex: sampler.input, gltf: gltf, binaryData: binaryData)
            maxTime = max(maxTime, times.last ?? 0)

            let node = gltf.nodes?[nodeIndex]
            let sourceRestRotation: simd_quatf
            if let r = node?.rotation, r.count == 4 {
                sourceRestRotation = simd_normalize(simd_quatf(ix: r[0], iy: r[1], iz: r[2], r: r[3]))
            } else {
                sourceRestRotation = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
            }

            if boneName == "hips", let t = node?.translation, t.count == 3 {
                hipsRestPosition = SIMD3<Float>(t[0], t[1], t[2])
            }

            switch channel.target.path {
            case "translation":
                guard boneName == "hips" else { continue }
                let values = try readVec3(accessorIndex: sampler.output, gltf: gltf, binaryData: binaryData)
                channels.append(VRMAChannel(
                    boneName: boneName,
                    times: times,
                    values: .translation(values),
                    sourceRestRotation: sourceRestRotation
                ))
            case "rotation":
                let values = try readQuat(accessorIndex: sampler.output, gltf: gltf, binaryData: binaryData)
                channels.append(VRMAChannel(
                    boneName: boneName,
                    times: times,
                    values: .rotation(values),
                    sourceRestRotation: sourceRestRotation
                ))
            default:
                continue
            }
        }

        return VRMAClip(duration: maxTime, channels: channels, sourceHipsRestPosition: hipsRestPosition)
    }

    /// Build node-index → humanoid bone name mapping.
    /// Prefers the `VRMC_vrm_animation` extension; falls back to node-name heuristics.
    private static func buildBoneMapping(gltf: VRMAGLTF) -> [Int: String] {
        var mapping: [Int: String] = [:]

        if let humanBones = gltf.extensions?.VRMC_vrm_animation?.humanoid?.humanBones {
            for (boneName, ref) in humanBones {
                mapping[ref.node] = boneName
            }
            return mapping
        }

        guard let nodes = gltf.nodes else { return mapping }
        for (index, node) in nodes.enumerated() {
            guard let name = node.name, !name.isEmpty else { continue }
            if let boneName = fallbackBoneName(from: name) {
                mapping[index] = boneName
            }
        }
        return mapping
    }

    /// Fallback: derive a humanoid bone name from a glTF node name.
    private static func fallbackBoneName(from nodeName: String) -> String? {
        let trimmed = nodeName.trimmingCharacters(in: .whitespacesAndNewlines)

        let camelCase = trimmed.prefix(1).lowercased() + trimmed.dropFirst()
        if allHumanoidBoneNames.contains(camelCase) {
            return camelCase
        }

        let compact = trimmed
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "_", with: "")
            .lowercased()

        if let alias = compactAliases[compact] {
            return alias
        }

        if compact.hasPrefix("jbipc") {
            return jBipCenterBone(compact: compact)
        }
        if compact.hasPrefix("jadj") && compact.contains("faceeye") {
            if compact.contains("lfaceeye") { return "leftEye" }
            if compact.contains("rfaceeye") { return "rightEye" }
        }
        if compact.hasPrefix("jbipl") || compact.hasPrefix("jbipr") {
            return jBipSideBone(compact: compact, isLeft: compact.hasPrefix("jbipl"))
        }
        return nil
    }

    private static let allHumanoidBoneNames: Set<String> = {
        var names: Set<String> = [
            "hips", "spine", "chest", "upperChest", "neck", "head", "jaw",
            "leftEye", "rightEye",
            "leftShoulder", "rightShoulder",
            "leftUpperArm", "rightUpperArm", "leftLowerArm", "rightLowerArm",
            "leftHand", "rightHand",
            "leftUpperLeg", "rightUpperLeg", "leftLowerLeg", "rightLowerLeg",
            "leftFoot", "rightFoot", "leftToes", "rightToes",
        ]
        for side in ["left", "right"] {
            for finger in ["Thumb", "Index", "Middle", "Ring", "Little"] {
                for segment in ["Proximal", "Intermediate", "Distal"] {
                    names.insert("\(side)\(finger)\(segment)")
                }
            }
        }
        return names
    }()

    private static let compactAliases: [String: String] = [
        "hips": "hips",
        "spine": "spine",
        "chest": "chest",
        "upperchest": "upperChest",
        "neck": "neck",
        "head": "head",
        "jaw": "jaw",
        "lefteye": "leftEye",
        "righteye": "rightEye",
        "leftshoulder": "leftShoulder",
        "rightshoulder": "rightShoulder",
        "leftupperarm": "leftUpperArm",
        "rightupperarm": "rightUpperArm",
        "leftlowerarm": "leftLowerArm",
        "rightlowerarm": "rightLowerArm",
        "lefthand": "leftHand",
        "righthand": "rightHand",
        "leftupperleg": "leftUpperLeg",
        "rightupperleg": "rightUpperLeg",
        "leftlowerleg": "leftLowerLeg",
        "rightlowerleg": "rightLowerLeg",
        "leftfoot": "leftFoot",
        "rightfoot": "rightFoot",
        "lefttoes": "leftToes",
        "righttoes": "rightToes",
    ]

    private static func jBipCenterBone(compact: String) -> String? {
        if compact.contains("hips") { return "hips" }
        if compact.contains("upperchest") { return "upperChest" }
        if compact.contains("chest") { return "chest" }
        if compact.contains("spine") { return "spine" }
        if compact.contains("neck") { return "neck" }
        if compact.contains("head") { return "head" }
        return nil
    }

    private static func jBipSideBone(compact: String, isLeft: Bool) -> String? {
        func pick(_ left: String, _ right: String) -> String { isLeft ? left : right }

        if compact.contains("shoulder") { return pick("leftShoulder", "rightShoulder") }
        if compact.contains("upperarm") { return pick("leftUpperArm", "rightUpperArm") }
        if compact.contains("lowerarm") { return pick("leftLowerArm", "rightLowerArm") }
        if compact.contains("hand") { return pick("leftHand", "rightHand") }
        if compact.contains("upperleg") { return pick("leftUpperLeg", "rightUpperLeg") }
        if compact.contains("lowerleg") { return pick("leftLowerLeg", "rightLowerLeg") }
        if compact.contains("foot") { return pick("leftFoot", "rightFoot") }
        if compact.contains("toebase") || compact.contains("toes") { return pick("leftToes", "rightToes") }
        if compact.contains("thumb3") { return pick("leftThumbDistal", "rightThumbDistal") }
        if compact.contains("thumb2") { return pick("leftThumbIntermediate", "rightThumbIntermediate") }
        if compact.contains("thumb1") { return pick("leftThumbProximal", "rightThumbProximal") }
        if compact.contains("index3") { return pick("leftIndexDistal", "rightIndexDistal") }
        if compact.contains("index2") { return pick("leftIndexIntermediate", "rightIndexIntermediate") }
        if compact.contains("index1") { return pick("leftIndexProximal", "rightIndexProximal") }
        if compact.contains("middle3") { return pick("leftMiddleDistal", "rightMiddleDistal") }
        if compact.contains("middle2") { return pick("leftMiddleIntermediate", "rightMiddleIntermediate") }
        if compact.contains("middle1") { return pick("leftMiddleProximal", "rightMiddleProximal") }
        if compact.contains("ring3") { return pick("leftRingDistal", "rightRingDistal") }
        if compact.contains("ring2") { return pick("leftRingIntermediate", "rightRingIntermediate") }
        if compact.contains("ring1") { return pick("leftRingProximal", "rightRingProximal") }
        if compact.contains("little3") { return pick("leftLittleDistal", "rightLittleDistal") }
        if compact.contains("little2") { return pick("leftLittleIntermediate", "rightLittleIntermediate") }
        if compact.contains("little1") { return pick("leftLittleProximal", "rightLittleProximal") }
        return nil
    }

    // MARK: - Binary GLB helpers

    private static func splitGLB(_ data: Data) throws -> (Data, Data) {
        guard data.count >= 20 else { throw VRMAPlayerError.invalidHeader }

        func readUInt32(at offset: Int) -> UInt32 {
            data.subdata(in: offset..<(offset + 4)).withUnsafeBytes { $0.load(as: UInt32.self) }
        }

        let magic = readUInt32(at: 0)
        guard magic == 0x46546C67 else { throw VRMAPlayerError.invalidHeader }

        let jsonLength = Int(readUInt32(at: 12))
        let jsonType = readUInt32(at: 16)
        guard jsonType == 0x4E4F534A else { throw VRMAPlayerError.invalidJSONChunk }
        let jsonStart = 20
        let jsonEnd = jsonStart + jsonLength
        let jsonData = data.subdata(in: jsonStart..<jsonEnd)

        guard data.count >= jsonEnd + 8 else { throw VRMAPlayerError.missingBinaryChunk }
        let binLength = Int(readUInt32(at: jsonEnd))
        let binStart = jsonEnd + 8
        let binEnd = min(binStart + binLength, data.count)
        let binaryData = data.subdata(in: binStart..<binEnd)
        return (jsonData, binaryData)
    }

    private static func accessorSlice(
        accessorIndex: Int,
        gltf: VRMAGLTF,
        binaryData: Data
    ) throws -> (Data, VRMAGLTF.Accessor, Int) {
        guard gltf.accessors.indices.contains(accessorIndex) else { throw VRMAPlayerError.unsupportedAccessor }
        let accessor = gltf.accessors[accessorIndex]
        guard accessor.componentType == 5126,
              let bufferViewIndex = accessor.bufferView,
              gltf.bufferViews.indices.contains(bufferViewIndex)
        else {
            throw VRMAPlayerError.unsupportedAccessor
        }
        let bufferView = gltf.bufferViews[bufferViewIndex]
        let offset = (bufferView.byteOffset ?? 0) + (accessor.byteOffset ?? 0)
        let stride = bufferView.byteStride ?? componentWidth(for: accessor.type)
        return (binaryData.advanced(by: offset), accessor, stride)
    }

    private static func readScalars(accessorIndex: Int, gltf: VRMAGLTF, binaryData: Data) throws -> [Float] {
        let (slice, accessor, stride) = try accessorSlice(accessorIndex: accessorIndex, gltf: gltf, binaryData: binaryData)
        guard accessor.type == "SCALAR" else { throw VRMAPlayerError.unsupportedAccessor }
        return (0..<accessor.count).map { index in
            readFloat(from: slice, offset: index * stride)
        }
    }

    private static func readVec3(accessorIndex: Int, gltf: VRMAGLTF, binaryData: Data) throws -> [SIMD3<Float>] {
        let (slice, accessor, stride) = try accessorSlice(accessorIndex: accessorIndex, gltf: gltf, binaryData: binaryData)
        guard accessor.type == "VEC3" else { throw VRMAPlayerError.unsupportedAccessor }
        return (0..<accessor.count).map { index in
            let base = index * stride
            return SIMD3<Float>(
                readFloat(from: slice, offset: base),
                readFloat(from: slice, offset: base + 4),
                readFloat(from: slice, offset: base + 8)
            )
        }
    }

    private static func readQuat(accessorIndex: Int, gltf: VRMAGLTF, binaryData: Data) throws -> [simd_quatf] {
        let (slice, accessor, stride) = try accessorSlice(accessorIndex: accessorIndex, gltf: gltf, binaryData: binaryData)
        guard accessor.type == "VEC4" else { throw VRMAPlayerError.unsupportedAccessor }
        return (0..<accessor.count).map { index in
            let base = index * stride
            let x = readFloat(from: slice, offset: base)
            let y = readFloat(from: slice, offset: base + 4)
            let z = readFloat(from: slice, offset: base + 8)
            let w = readFloat(from: slice, offset: base + 12)
            return simd_normalize(simd_quatf(ix: x, iy: y, iz: z, r: w))
        }
    }

    private static func readFloat(from data: Data, offset: Int) -> Float {
        data.subdata(in: offset..<(offset + 4)).withUnsafeBytes { $0.load(as: Float.self) }
    }

    private static func componentWidth(for type: String) -> Int {
        switch type {
        case "SCALAR": return 4
        case "VEC3": return 12
        case "VEC4": return 16
        default: return 4
        }
    }
}

// MARK: - VRoid Pose Player

private struct VRoidPoseFile: Decodable {
    let BoneDefinition: [String: PoseValue]

    enum PoseValue: Decodable {
        case vec3(x: Float, y: Float, z: Float)
        case quat(x: Float, y: Float, z: Float, w: Float)

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let x = try container.decode(Float.self, forKey: .x)
            let y = try container.decode(Float.self, forKey: .y)
            let z = try container.decode(Float.self, forKey: .z)
            if let w = try container.decodeIfPresent(Float.self, forKey: .w) {
                self = .quat(x: x, y: y, z: z, w: w)
            } else {
                self = .vec3(x: x, y: y, z: z)
            }
        }

        enum CodingKeys: String, CodingKey { case x, y, z, w }
    }
}

private struct VRoidPoseTarget {
    let hipsPosition: SIMD3<Float>
    var boneRotations: [(boneName: String, rotation: simd_quatf)]
}

@MainActor
final class VRoidPosePlayer {
    private let target: VRoidPoseTarget
    private weak var vrmEntity: VRMEntity?
    private let boneRestTransforms: [Humanoid.Bones: Transform]
    private weak var chestEntity: Entity?
    private let chestRestTransform: Transform?
    private let modelHipsRestY: Float

    private var currentTime: Float = 0
    private let transitionDuration: Float = 0.65

    private var snapshotRotations: [String: simd_quatf] = [:]
    private var snapshotHipsPosition: SIMD3<Float> = .zero

    private static let faceBoneNames: Set<String> = ["leftEye", "rightEye", "jaw"]

    init(
        filePath: String,
        vrmEntity: VRMEntity,
        restTransforms: [Humanoid.Bones: Transform],
        chestEntity: Entity?,
        chestRestTransform: Transform?,
        convention: VRMCoordinateConvention = .v0
    ) throws {
        self.target = try Self.loadPose(filePath: filePath, convention: convention)
        self.vrmEntity = vrmEntity
        self.boneRestTransforms = restTransforms
        self.chestEntity = chestEntity
        self.chestRestTransform = chestRestTransform
        self.modelHipsRestY = restTransforms[.hips]?.translation.y ?? 0.75
        captureSnapshot(from: vrmEntity)
    }

    func update(deltaTime: TimeInterval) {
        guard let vrmEntity else { return }

        currentTime += Float(deltaTime)
        let rawT = min(1.0, currentTime / transitionDuration)
        let t = rawT * rawT * (3 - 2 * rawT) // smoothstep

        let scale = modelHipsRestY / max(target.hipsPosition.y, 0.01)

        for (boneName, targetRotation) in target.boneRotations {
            let camelName = Self.toCamelCase(boneName)

            if Self.faceBoneNames.contains(camelName) { continue }

            if camelName == "chest" {
                if let chestEntity, let chestRest = chestRestTransform {
                    let from = snapshotRotations["chest"] ?? chestRest.rotation
                    chestEntity.transform.rotation = simd_slerp(from, targetRotation, t)
                }
                continue
            }

            guard let bone = Humanoid.Bones(rawValue: camelName),
                  let entity = vrmEntity.humanoid.node(for: bone) else { continue }

            let rest = boneRestTransforms[bone]?.translation
            let from = snapshotRotations[camelName]
                ?? boneRestTransforms[bone]?.rotation
                ?? entity.transform.rotation

            entity.transform.rotation = simd_slerp(from, targetRotation, t)

            if bone == .hips {
                let targetPos = SIMD3<Float>(
                    target.hipsPosition.x * scale,
                    target.hipsPosition.y * scale,
                    target.hipsPosition.z * scale
                )
                let fromPos = snapshotHipsPosition
                entity.transform.translation = simd_mix(fromPos, targetPos, SIMD3(repeating: t))
            } else if let rest {
                entity.transform.translation = rest
            }
        }
    }

    // MARK: - Snapshot

    private func captureSnapshot(from vrmEntity: VRMEntity) {
        for (boneName, _) in target.boneRotations {
            let camelName = Self.toCamelCase(boneName)

            if camelName == "chest" {
                snapshotRotations["chest"] = chestEntity?.transform.rotation
                continue
            }
            if let bone = Humanoid.Bones(rawValue: camelName),
               let entity = vrmEntity.humanoid.node(for: bone) {
                snapshotRotations[camelName] = entity.transform.rotation
                if bone == .hips {
                    snapshotHipsPosition = entity.transform.translation
                }
            }
        }
    }

    // MARK: - Parsing

    /// Unity → VRM 0.x (Z-axis reflection): negate Qx, Qy.
    private static func convertToVRM0(_ q: simd_quatf) -> simd_quatf {
        simd_quatf(ix: -q.imag.x, iy: -q.imag.y, iz: q.imag.z, r: q.real)
    }

    /// Unity → VRM 1.0 (X-axis reflection): negate Qy, Qz.
    private static func convertToVRM1(_ q: simd_quatf) -> simd_quatf {
        simd_quatf(ix: q.imag.x, iy: -q.imag.y, iz: -q.imag.z, r: q.real)
    }

    private static func loadPose(filePath: String, convention: VRMCoordinateConvention) throws -> VRoidPoseTarget {
        let data = try Data(contentsOf: URL(fileURLWithPath: filePath))
        let file = try JSONDecoder().decode(VRoidPoseFile.self, from: data)

        var hipsPosition = SIMD3<Float>(0, 1.0, 0)
        var boneRotations: [(String, simd_quatf)] = []

        for (key, value) in file.BoneDefinition {
            switch (key, value) {
            case ("HipsPosition", .vec3(let x, let y, let z)):
                switch convention {
                case .v0: hipsPosition = SIMD3<Float>(x, y, -z)
                case .v1: hipsPosition = SIMD3<Float>(-x, y, z)
                }
            case ("SpineControlPointDeltaPosition", _):
                continue
            case (_, .quat(let x, let y, let z, let w)):
                let raw = simd_normalize(simd_quatf(ix: x, iy: y, iz: z, r: w))
                switch convention {
                case .v0: boneRotations.append((key, convertToVRM0(raw)))
                case .v1: boneRotations.append((key, convertToVRM1(raw)))
                }
            default:
                continue
            }
        }

        return VRoidPoseTarget(hipsPosition: hipsPosition, boneRotations: boneRotations)
    }

    private static func toCamelCase(_ pascalCase: String) -> String {
        guard let first = pascalCase.first else { return pascalCase }
        return first.lowercased() + pascalCase.dropFirst()
    }
}
