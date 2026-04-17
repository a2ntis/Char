import Foundation
import simd

// MARK: - Public types

struct CompanionBVHOption: Identifiable, Hashable {
    let id: String
    let displayName: String
    let filePath: String
}

// MARK: - Catalog

enum BVHCatalog {
    static func discover(in assetsRoot: URL) -> [CompanionBVHOption] {
        let folder = assetsRoot.appendingPathComponent("BVH", isDirectory: true)
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        return enumerator
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension.lowercased() == "bvh" }
            .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
            .map {
                CompanionBVHOption(
                    id: $0.path,
                    displayName: prettifyName($0.deletingPathExtension().lastPathComponent),
                    filePath: $0.path
                )
            }
    }

    private static func prettifyName(_ rawName: String) -> String {
        let withoutPrefix = rawName.replacingOccurrences(
            of: #"^\d+[_\-\s]*"#, with: "", options: .regularExpression)
        return withoutPrefix
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Converter

enum BVHConverterError: Error, LocalizedError {
    case parseError(String)
    case noFrames
    case noMappedBones

    var errorDescription: String? {
        switch self {
        case .parseError(let msg): return "BVH parse error: \(msg)"
        case .noFrames: return "BVH has no motion frames"
        case .noMappedBones: return "BVH: no bones could be mapped to VRM humanoid"
        }
    }
}

enum BVHConverter {
    /// Convert a BVH file to VRMA format, caching to the system temp directory.
    /// Returns the path to the generated .vrma file.
    static func vrmaPath(for bvhPath: String) throws -> String {
        let cacheDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("bvh_vrma_cache", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)

        let stem = URL(fileURLWithPath: bvhPath).deletingPathExtension().lastPathComponent
        let cacheURL = cacheDir.appendingPathComponent(stem + ".vrma")

        let bvhMod = (try? FileManager.default.attributesOfItem(atPath: bvhPath)[.modificationDate] as? Date)
            ?? Date.distantPast
        let cacheMod = (try? FileManager.default.attributesOfItem(atPath: cacheURL.path)[.modificationDate] as? Date)
            ?? Date.distantPast

        if FileManager.default.fileExists(atPath: cacheURL.path), cacheMod >= bvhMod {
            return cacheURL.path
        }

        let text = try String(contentsOfFile: bvhPath, encoding: .utf8)
        let data = try bvhToVRMAData(text: text)
        try data.write(to: cacheURL)
        return cacheURL.path
    }
}

// MARK: - BVH channel types

private enum BVHChannelType: Equatable {
    case xPos, yPos, zPos
    case xRot, yRot, zRot

    var isRotation: Bool { self == .xRot || self == .yRot || self == .zRot }
    var isTranslation: Bool { self == .xPos || self == .yPos || self == .zPos }
}

// MARK: - BVH parsed types

private struct BVHJoint {
    let rawName: String
    let vrmName: String?          // nil if this bone has no VRM equivalent
    let channels: [BVHChannelType]
    let channelOffset: Int        // index of first channel in the flat frame array
}

private struct BVHFile {
    let joints: [BVHJoint]
    let frameCount: Int
    let frameTime: Float          // seconds per frame
    let frames: [[Float]]         // [frameIndex][flatChannelIndex]
    let totalChannels: Int
}

// MARK: - BVH Parser

private func parseBVH(text: String) throws -> BVHFile {
    var tokens = text
        .components(separatedBy: .whitespacesAndNewlines)
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }

    var idx = 0

    func peek() -> String? { idx < tokens.count ? tokens[idx] : nil }
    func consume() -> String? {
        guard idx < tokens.count else { return nil }
        defer { idx += 1 }
        return tokens[idx]
    }
    func need() throws -> String {
        guard let t = consume() else {
            throw BVHConverterError.parseError("Unexpected end of file")
        }
        return t
    }
    func needFloat() throws -> Float {
        let t = try need()
        guard let v = Float(t) else {
            throw BVHConverterError.parseError("Expected float, got '\(t)'")
        }
        return v
    }
    func needInt() throws -> Int {
        let t = try need()
        let s = t.hasSuffix(":") ? String(t.dropLast()) : t
        guard let v = Int(s) else {
            throw BVHConverterError.parseError("Expected int, got '\(t)'")
        }
        return v
    }
    /// Consume one token, ignoring its value (e.g. skip "OFFSET", "Site", "{"…).
    func skip(_ expected: String) throws {
        guard let t = peek() else {
            throw BVHConverterError.parseError("Expected '\(expected)' but got EOF")
        }
        let normalized = t.hasSuffix(":") ? String(t.dropLast()) : t
        guard normalized.uppercased() == expected.uppercased() else {
            throw BVHConverterError.parseError("Expected '\(expected)' but got '\(t)'")
        }
        idx += 1
    }
    func peekUpper() -> String? {
        guard let t = peek() else { return nil }
        return (t.hasSuffix(":") ? String(t.dropLast()) : t).uppercased()
    }

    try skip("HIERARCHY")

    var joints: [BVHJoint] = []
    var channelCursor = 0
    var usedVRMNames = Set<String>()

    // Recursive joint parser; handles ROOT, JOINT, and End Site.
    func parseJoint() throws {
        guard let kw = peek() else {
            throw BVHConverterError.parseError("Expected ROOT/JOINT/End")
        }
        let kwUpper = kw.uppercased()

        if kwUpper == "END" {
            idx += 1
            if peek()?.uppercased() == "SITE" { idx += 1 }
            try skip("{")
            try skip("OFFSET")
            _ = try needFloat(); _ = try needFloat(); _ = try needFloat()
            try skip("}")
            return
        }

        guard kwUpper == "ROOT" || kwUpper == "JOINT" else {
            throw BVHConverterError.parseError("Expected ROOT/JOINT/End, got '\(kw)'")
        }
        idx += 1

        let rawName = try need()
        try skip("{")
        try skip("OFFSET")
        _ = try needFloat(); _ = try needFloat(); _ = try needFloat()

        var channels: [BVHChannelType] = []
        if peekUpper() == "CHANNELS" {
            idx += 1
            let count = try needInt()
            for _ in 0..<count {
                let ch = try need()
                switch ch.uppercased() {
                case "XPOSITION": channels.append(.xPos)
                case "YPOSITION": channels.append(.yPos)
                case "ZPOSITION": channels.append(.zPos)
                case "XROTATION": channels.append(.xRot)
                case "YROTATION": channels.append(.yRot)
                case "ZROTATION": channels.append(.zRot)
                default: channels.append(.xRot)
                }
            }
        }

        let mapped = mapBVHBoneName(rawName)
        let effective: String?
        if let m = mapped, !usedVRMNames.contains(m) {
            usedVRMNames.insert(m)
            effective = m
        } else {
            effective = nil
        }

        joints.append(BVHJoint(
            rawName: rawName,
            vrmName: effective,
            channels: channels,
            channelOffset: channelCursor
        ))
        channelCursor += channels.count

        // Parse children until closing brace
        while let next = peek(), next != "}" {
            if next.uppercased() == "JOINT" || next.uppercased() == "END" {
                try parseJoint()
            } else if next.uppercased() == "ROOT" {
                try parseJoint()
            } else {
                // Skip unexpected token
                idx += 1
            }
        }
        try skip("}")
    }

    // One or more top-level ROOT joints
    while peekUpper() == "ROOT" {
        try parseJoint()
    }

    // MOTION section
    try skip("MOTION")
    try skip("Frames")    // handles "Frames:" because skip strips trailing ":"
    let frameCount = try needInt()
    // "Frame Time:" — two tokens: "Frame" and "Time:"
    try skip("Frame")
    try skip("Time")      // handles "Time:"
    let frameTime = try needFloat()

    let totalChannels = channelCursor
    var frames: [[Float]] = []
    frames.reserveCapacity(frameCount)

    for _ in 0..<frameCount {
        var row = [Float]()
        row.reserveCapacity(totalChannels)
        for _ in 0..<totalChannels {
            row.append(try needFloat())
        }
        frames.append(row)
    }

    guard !frames.isEmpty else { throw BVHConverterError.noFrames }

    return BVHFile(
        joints: joints,
        frameCount: frames.count,
        frameTime: frameTime,
        frames: frames,
        totalChannels: totalChannels
    )
}

// MARK: - BVH → VRM bone name mapping

/// Normalise a BVH bone name for dictionary lookup.
private func normaliseBVHName(_ raw: String) -> String {
    var s = raw
    // Strip common namespace prefixes
    for prefix in ["mixamorig:", "mixamorig_", "bip01_", "bip001_", "bip_", "cs_"] {
        if s.lowercased().hasPrefix(prefix) {
            s = String(s.dropFirst(prefix.count))
            break
        }
    }
    return s
        .replacingOccurrences(of: " ", with: "")
        .replacingOccurrences(of: "_", with: "")
        .replacingOccurrences(of: "-", with: "")
        .lowercased()
}

private func mapBVHBoneName(_ raw: String) -> String? {
    bvhToVRM[normaliseBVHName(raw)]
}

private let bvhToVRM: [String: String] = {
    var m: [String: String] = [:]

    // ── VRM humanoid bone names used directly in these BVH packs ──────────
    // Many BVH exporters (VRoid, Blender VRM plugin) already output VRM names.
    // Map lowercase → canonical camelCase for every VRM humanoid bone.

    // Core
    m["hips"]       = "hips"
    m["spine"]      = "spine"
    m["chest"]      = "chest"
    m["upperchest"] = "upperChest"
    m["neck"]       = "neck"
    m["head"]       = "head"
    m["jaw"]        = "jaw"
    m["lefteye"]    = "leftEye"
    m["righteye"]   = "rightEye"

    // Arms
    for side in ["left", "right"] {
        m["\(side)shoulder"]  = "\(side)Shoulder"
        m["\(side)upperarm"]  = "\(side)UpperArm"
        m["\(side)lowerarm"]  = "\(side)LowerArm"
        m["\(side)hand"]      = "\(side)Hand"
        // Fingers (non-thumb)
        for finger in ["index", "middle", "ring", "little"] {
            let F = finger.prefix(1).uppercased() + finger.dropFirst()
            m["\(side)\(finger)proximal"]     = "\(side)\(F)Proximal"
            m["\(side)\(finger)intermediate"] = "\(side)\(F)Intermediate"
            m["\(side)\(finger)distal"]       = "\(side)\(F)Distal"
        }
        // Thumb — BVH files typically use 3 bones named Proximal/Intermediate/Distal
        // but VRM uses Metacarpal/Proximal/Distal.  Shift by one level:
        m["\(side)thumbmetacarpal"]   = "\(side)ThumbMetacarpal"  // if already VRM-named
        m["\(side)thumbproximal"]     = "\(side)ThumbMetacarpal"  // BVH Proximal → VRM Metacarpal
        m["\(side)thumbintermediate"] = "\(side)ThumbProximal"    // BVH Intermediate → VRM Proximal
        m["\(side)thumbdistal"]       = "\(side)ThumbDistal"
    }

    // Legs
    for side in ["left", "right"] {
        m["\(side)upperleg"] = "\(side)UpperLeg"
        m["\(side)lowerleg"] = "\(side)LowerLeg"
        m["\(side)foot"]     = "\(side)Foot"
        m["\(side)toes"]     = "\(side)Toes"
    }

    // ── Aliases for non-VRM BVH conventions ───────────────────────────────
    // Hips
    for k in ["hip", "pelvis", "root", "reference"] { m[k] = "hips" }

    // Spine chain (generic numbering)
    m["spine1"]    = "spine"
    m["lowerback"] = "spine"
    m["abdomen"]   = "spine"
    m["spine2"]    = "chest"
    m["spine3"]    = "chest"
    m["thorax"]    = "chest"
    m["upperback"] = "chest"
    m["spine4"]    = "upperChest"
    m["spine5"]    = "upperChest"

    // Neck & head aliases
    m["neck1"] = "neck"

    // Left arm aliases
    for k in ["lshoulder", "lcollar", "leftcollar", "lclavicle", "leftclavicle"] { m[k] = "leftShoulder" }
    for k in ["leftarm", "larm", "lupperarm", "leftshldr", "lshldr", "lhumerus"]  { m[k] = "leftUpperArm" }
    for k in ["leftforearm", "lforearm", "lelbow", "leftradius", "lradius"]       { m[k] = "leftLowerArm" }
    for k in ["lwrist", "lhand"]                                                  { m[k] = "leftHand" }

    // Right arm aliases
    for k in ["rshoulder", "rcollar", "rightcollar", "rclavicle", "rightclavicle"] { m[k] = "rightShoulder" }
    for k in ["rightarm", "rarm", "rupperarm", "rightshldr", "rshldr", "rhumerus"] { m[k] = "rightUpperArm" }
    for k in ["rightforearm", "rforearm", "relbow", "rightradius", "rradius"]      { m[k] = "rightLowerArm" }
    for k in ["rwrist", "rhand"]                                                   { m[k] = "rightHand" }

    // Leg aliases
    for k in ["leftupleg", "lupleg", "lthigh", "leftthigh", "lfemur", "leftfemur"]   { m[k] = "leftUpperLeg" }
    for k in ["leftleg", "lleg", "lshin", "leftshin", "ltibia", "lefttibia"]         { m[k] = "leftLowerLeg" }
    for k in ["lfoot"]                                                                { m[k] = "leftFoot" }
    for k in ["lefttoe", "lefttoebase", "ltoebase", "ltoe"]                          { m[k] = "leftToes" }
    for k in ["rightupleg", "rupleg", "rthigh", "rightthigh", "rfemur", "rightfemur"] { m[k] = "rightUpperLeg" }
    for k in ["rightleg", "rleg", "rshin", "rightshin", "rtibia", "righttibia"]       { m[k] = "rightLowerLeg" }
    for k in ["rfoot"]                                                                 { m[k] = "rightFoot" }
    for k in ["righttoe", "righttoebase", "rtoebase", "rtoe"]                         { m[k] = "rightToes" }

    return m
}()

// MARK: - Euler → Quaternion

/// Convert BVH Euler angles (degrees) to a quaternion for a single frame.
/// Uses the convention: iterate rotation channels in FORWARD order, right-multiply.
///   result = q_ch_0 * q_ch_1 * ... * q_ch_N
/// For channels [Yrot, Xrot, Zrot] this gives q = qY * qX * qZ,
/// meaning qZ is applied to the vector first (innermost), qY last (outermost).
/// This matches the Three.js BVHLoader / Euler('YXZ') quaternion convention.
private func eulerToQuat(channels: [BVHChannelType], frameData: [Float], baseOffset: Int) -> simd_quatf {
    let deg2rad: Float = .pi / 180.0
    var result = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)

    for (localIdx, ch) in channels.enumerated() {
        let angle = frameData[baseOffset + localIdx] * deg2rad
        let q: simd_quatf
        switch ch {
        case .xRot: q = simd_quatf(angle: angle, axis: SIMD3<Float>(1, 0, 0))
        case .yRot: q = simd_quatf(angle: angle, axis: SIMD3<Float>(0, 1, 0))
        case .zRot: q = simd_quatf(angle: angle, axis: SIMD3<Float>(0, 0, 1))
        default: continue
        }
        result = result * q   // right-multiply: first channel wraps outermost
    }
    return simd_normalize(result)
}

// MARK: - BVH → VRMA GLB conversion

private let bvhScaleToCM: Float = 0.01   // BVH units (cm) → VRM units (m)

private func bvhToVRMAData(text: String) throws -> Data {
    let bvh = try parseBVH(text: text)
    let N = bvh.frameCount
    let dt = bvh.frameTime

    // Collect joints that have a VRM name
    let mappedJoints = bvh.joints.filter { $0.vrmName != nil }
    guard !mappedJoints.isEmpty else { throw BVHConverterError.noMappedBones }

    // Separate hips (for translation) from all joints (for rotation)
    let hipsJoint = bvh.joints.first { $0.vrmName == "hips" }

    // Build time track
    let times: [Float] = (0..<N).map { Float($0) * dt }

    // Build hips translation track (if hips has position channels)
    var hipsTranslations: [SIMD3<Float>]? = nil
    if let h = hipsJoint {
        let hasPos = h.channels.contains { $0.isTranslation }
        if hasPos {
            var xIdx: Int? = nil, yIdx: Int? = nil, zIdx: Int? = nil
            for (i, ch) in h.channels.enumerated() {
                switch ch {
                case .xPos: xIdx = i
                case .yPos: yIdx = i
                case .zPos: zIdx = i
                default: break
                }
            }
            hipsTranslations = bvh.frames.map { row in
                let base = h.channelOffset
                let x = xIdx.map { row[base + $0] * bvhScaleToCM } ?? 0
                let y = yIdx.map { row[base + $0] * bvhScaleToCM } ?? 0
                let z = zIdx.map { row[base + $0] * bvhScaleToCM } ?? 0
                return SIMD3<Float>(x, y, z)
            }
        }
    }

    // Build rotation tracks per mapped joint
    // Each entry: (vrmName, [simd_quatf] × N)
    var rotationTracks: [(vrmName: String, quats: [simd_quatf])] = []
    for joint in mappedJoints {
        guard let vrmName = joint.vrmName else { continue }
        let hasRot = joint.channels.contains { $0.isRotation }
        guard hasRot else { continue }
        let quats: [simd_quatf] = bvh.frames.map { row in
            eulerToQuat(channels: joint.channels, frameData: row, baseOffset: joint.channelOffset)
        }
        rotationTracks.append((vrmName, quats))
    }

    // ── Assemble binary buffer ──────────────────────────────────────────────
    // Layout:
    //   [0]  time: float32 × N
    //   [1]  hips translation: float32 × N×3  (optional)
    //   [2…] bone rotations: float32 × N×4 per bone

    var bin = Data()

    func appendFloat(_ v: Float) {
        var val = v
        withUnsafeBytes(of: &val) { bin.append(contentsOf: $0) }
    }

    let timeOffset = 0
    for t in times { appendFloat(t) }
    let timeByteLen = bin.count

    var transOffset: Int? = nil
    var transByteLen: Int = 0
    if let trans = hipsTranslations {
        transOffset = bin.count
        for v in trans {
            appendFloat(v.x); appendFloat(v.y); appendFloat(v.z)
        }
        transByteLen = bin.count - transOffset!
    }

    var rotOffsets: [Int] = []
    for (_, quats) in rotationTracks {
        rotOffsets.append(bin.count)
        for q in quats {
            appendFloat(q.imag.x); appendFloat(q.imag.y); appendFloat(q.imag.z); appendFloat(q.real)
        }
    }

    // Pad binary to 4-byte alignment
    while bin.count % 4 != 0 { bin.append(0x00) }
    let totalBinBytes = bin.count

    // ── Build glTF JSON ─────────────────────────────────────────────────────

    // Buffer views and accessors
    var bufferViews: [[String: Any]] = []
    var accessors: [[String: Any]] = []

    func addBV(offset: Int, byteLen: Int) -> Int {
        bufferViews.append([
            "buffer": 0,
            "byteOffset": offset,
            "byteLength": byteLen
        ])
        return bufferViews.count - 1
    }
    func addAccessor(bv: Int, count: Int, type: String, componentType: Int = 5126,
                     minValues: [Double]? = nil, maxValues: [Double]? = nil) -> Int {
        var acc: [String: Any] = [
            "bufferView": bv,
            "componentType": componentType,
            "count": count,
            "type": type
        ]
        if let mn = minValues { acc["min"] = mn }
        if let mx = maxValues { acc["max"] = mx }
        accessors.append(acc)
        return accessors.count - 1
    }

    // Time accessor (index 0)
    let timeBV = addBV(offset: timeOffset, byteLen: timeByteLen)
    let timeAcc = addAccessor(bv: timeBV, count: N, type: "SCALAR",
                              minValues: [0.0], maxValues: [Double(times.last ?? 0)])

    // Hips translation accessor (index 1, optional)
    var transAcc: Int? = nil
    if let to = transOffset {
        let bv = addBV(offset: to, byteLen: transByteLen)
        transAcc = addAccessor(bv: bv, count: N, type: "VEC3")
    }

    // Rotation accessors (indices 2…)
    var rotAccIndices: [Int] = []
    for (i, (_, _)) in rotationTracks.enumerated() {
        let offset = rotOffsets[i]
        let byteLen = N * 16  // N * 4 floats * 4 bytes
        let bv = addBV(offset: offset, byteLen: byteLen)
        rotAccIndices.append(addAccessor(bv: bv, count: N, type: "VEC4"))
    }

    // Nodes (one per mapped bone that has a rotation track, or hips with translation)
    var nodes: [[String: Any]] = []
    var nodeIndexForVRM: [String: Int] = [:]

    // Add hips node with translation if present
    if let trans = hipsTranslations, let firstTrans = trans.first {
        let nodeIdx = nodes.count
        nodes.append(["name": "hips",
                      "translation": [Double(firstTrans.x), Double(firstTrans.y), Double(firstTrans.z)]])
        nodeIndexForVRM["hips"] = nodeIdx
    }

    // Add nodes for all rotation tracks (hips may already exist)
    for (vrmName, _) in rotationTracks {
        if nodeIndexForVRM[vrmName] == nil {
            let nodeIdx = nodes.count
            nodes.append(["name": vrmName])
            nodeIndexForVRM[vrmName] = nodeIdx
        }
    }

    // Samplers and channels
    var samplers: [[String: Any]] = []
    var channels: [[String: Any]] = []

    // Hips translation sampler/channel
    if let tAcc = transAcc, let hipsNodeIdx = nodeIndexForVRM["hips"] {
        let samplerIdx = samplers.count
        samplers.append(["input": timeAcc, "output": tAcc, "interpolation": "LINEAR"])
        channels.append(["sampler": samplerIdx,
                         "target": ["node": hipsNodeIdx, "path": "translation"]])
    }

    // Rotation samplers/channels
    for (i, (vrmName, _)) in rotationTracks.enumerated() {
        guard let nodeIdx = nodeIndexForVRM[vrmName] else { continue }
        let samplerIdx = samplers.count
        samplers.append(["input": timeAcc, "output": rotAccIndices[i], "interpolation": "LINEAR"])
        channels.append(["sampler": samplerIdx,
                         "target": ["node": nodeIdx, "path": "rotation"]])
    }

    // humanBones for VRMC_vrm_animation extension
    var humanBones: [String: Any] = [:]
    for (vrmName, nodeIdx) in nodeIndexForVRM {
        humanBones[vrmName] = ["node": nodeIdx]
    }

    let gltfDict: [String: Any] = [
        "asset": ["version": "2.0", "generator": "CharApp BVH Converter"],
        "extensionsUsed": ["VRMC_vrm_animation"],
        "buffers": [["byteLength": totalBinBytes]],
        "bufferViews": bufferViews,
        "accessors": accessors,
        "nodes": nodes,
        "animations": [["samplers": samplers, "channels": channels]],
        "extensions": [
            "VRMC_vrm_animation": [
                "specVersion": "1.0",
                "humanoid": ["humanBones": humanBones]
            ]
        ]
    ]

    let jsonData = try JSONSerialization.data(withJSONObject: gltfDict, options: [])
    // Pad JSON to 4-byte alignment with spaces
    var paddedJSON = jsonData
    while paddedJSON.count % 4 != 0 { paddedJSON.append(0x20) }

    // ── Assemble GLB ────────────────────────────────────────────────────────
    let jsonChunkLen = paddedJSON.count
    let binChunkLen  = bin.count
    let totalLen = 12 + 8 + jsonChunkLen + 8 + binChunkLen

    var glb = Data()
    glb.reserveCapacity(totalLen)

    func appendUInt32(_ v: UInt32) {
        var val = v.littleEndian
        withUnsafeBytes(of: &val) { glb.append(contentsOf: $0) }
    }

    // GLB header
    appendUInt32(0x46546C67)        // magic "glTF"
    appendUInt32(2)                  // version
    appendUInt32(UInt32(totalLen))   // total length

    // JSON chunk
    appendUInt32(UInt32(jsonChunkLen))
    appendUInt32(0x4E4F534A)        // "JSON"
    glb.append(paddedJSON)

    // Binary chunk
    appendUInt32(UInt32(binChunkLen))
    appendUInt32(0x004E4942)        // "BIN\0"
    glb.append(bin)

    return glb
}
