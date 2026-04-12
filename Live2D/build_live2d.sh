#!/bin/zsh
set -euo pipefail

ROOT="/Users/denis_work/projects/Other/Char"
SDK="$ROOT/ThirdParty/CubismSdkForNative-5-r.5"
OUT="$ROOT/Live2D/build"
BIN="$OUT/CharShizuku"

mkdir -p "$OUT"

FRAMEWORK_SOURCES=(
  "$SDK/Framework/src/CubismCdiJson.cpp"
  "$SDK/Framework/src/CubismDefaultParameterId.cpp"
  "$SDK/Framework/src/CubismFramework.cpp"
  "$SDK/Framework/src/CubismModelSettingJson.cpp"
  "$SDK/Framework/src/Effect/CubismBreath.cpp"
  "$SDK/Framework/src/Effect/CubismEyeBlink.cpp"
  "$SDK/Framework/src/Effect/CubismLook.cpp"
  "$SDK/Framework/src/Effect/CubismPose.cpp"
  "$SDK/Framework/src/Id/CubismId.cpp"
  "$SDK/Framework/src/Id/CubismIdManager.cpp"
  "$SDK/Framework/src/Math/CubismMath.cpp"
  "$SDK/Framework/src/Math/CubismMatrix44.cpp"
  "$SDK/Framework/src/Math/CubismModelMatrix.cpp"
  "$SDK/Framework/src/Math/CubismTargetPoint.cpp"
  "$SDK/Framework/src/Math/CubismVector2.cpp"
  "$SDK/Framework/src/Math/CubismViewMatrix.cpp"
  "$SDK/Framework/src/Model/CubismMoc.cpp"
  "$SDK/Framework/src/Model/CubismModel.cpp"
  "$SDK/Framework/src/Model/CubismModelMultiplyAndScreenColor.cpp"
  "$SDK/Framework/src/Model/CubismModelUserData.cpp"
  "$SDK/Framework/src/Model/CubismModelUserDataJson.cpp"
  "$SDK/Framework/src/Model/CubismUserModel.cpp"
  "$SDK/Framework/src/Motion/ACubismMotion.cpp"
  "$SDK/Framework/src/Motion/CubismBreathUpdater.cpp"
  "$SDK/Framework/src/Motion/CubismExpressionMotion.cpp"
  "$SDK/Framework/src/Motion/CubismExpressionMotionManager.cpp"
  "$SDK/Framework/src/Motion/CubismExpressionUpdater.cpp"
  "$SDK/Framework/src/Motion/CubismEyeBlinkUpdater.cpp"
  "$SDK/Framework/src/Motion/CubismLipSyncUpdater.cpp"
  "$SDK/Framework/src/Motion/CubismLookUpdater.cpp"
  "$SDK/Framework/src/Motion/CubismMotion.cpp"
  "$SDK/Framework/src/Motion/CubismMotionJson.cpp"
  "$SDK/Framework/src/Motion/CubismMotionManager.cpp"
  "$SDK/Framework/src/Motion/CubismMotionQueueEntry.cpp"
  "$SDK/Framework/src/Motion/CubismMotionQueueManager.cpp"
  "$SDK/Framework/src/Motion/CubismPhysicsUpdater.cpp"
  "$SDK/Framework/src/Motion/CubismPoseUpdater.cpp"
  "$SDK/Framework/src/Motion/CubismUpdateScheduler.cpp"
  "$SDK/Framework/src/Motion/ICubismUpdater.cpp"
  "$SDK/Framework/src/Motion/IParameterProvider.cpp"
  "$SDK/Framework/src/Physics/CubismPhysics.cpp"
  "$SDK/Framework/src/Physics/CubismPhysicsJson.cpp"
  "$SDK/Framework/src/Rendering/csmBlendMode.cpp"
  "$SDK/Framework/src/Rendering/CubismRenderer.cpp"
  "$SDK/Framework/src/Rendering/OpenGL/CubismOffscreenManager_OpenGLES2.cpp"
  "$SDK/Framework/src/Rendering/OpenGL/CubismOffscreenRenderTarget_OpenGLES2.cpp"
  "$SDK/Framework/src/Rendering/OpenGL/CubismRenderTarget_OpenGLES2.cpp"
  "$SDK/Framework/src/Rendering/OpenGL/CubismRenderer_OpenGLES2.cpp"
  "$SDK/Framework/src/Rendering/OpenGL/CubismShader_OpenGLES2.cpp"
  "$SDK/Framework/src/Type/csmRectF.cpp"
  "$SDK/Framework/src/Type/csmString.cpp"
  "$SDK/Framework/src/Utils/CubismDebug.cpp"
  "$SDK/Framework/src/Utils/CubismJson.cpp"
  "$SDK/Framework/src/Utils/CubismString.cpp"
)

COMMON_SOURCES=(
  "$SDK/Samples/Common/CubismSampleViewMatrix_Common.cpp"
  "$SDK/Samples/Common/LAppAllocator_Common.cpp"
  "$SDK/Samples/Common/LAppModel_Common.cpp"
  "$SDK/Samples/Common/LAppSprite_Common.cpp"
  "$SDK/Samples/Common/LAppTextureManager_Common.cpp"
  "$SDK/Samples/Common/LAppView_Common.cpp"
  "$SDK/Samples/Common/LAppWavFileHandler_Common.cpp"
  "$SDK/Samples/Common/MouseActionManager_Common.cpp"
  "$SDK/Samples/Common/TouchManager_Common.cpp"
)

SAMPLE_SOURCES=(
  "$SDK/Samples/OpenGL/Demo/proj.mac.cmake/src/LAppDefine.cpp"
  "$SDK/Samples/OpenGL/Demo/proj.mac.cmake/src/LAppPal.cpp"
  "$SDK/Samples/OpenGL/Demo/proj.mac.cmake/src/LAppTextureManager.cpp"
  "$SDK/Samples/OpenGL/Demo/proj.mac.cmake/src/CubismUserModelExtend.cpp"
  "$SDK/Samples/OpenGL/Demo/proj.mac.cmake/src/MouseActionManager.cpp"
  "$ROOT/Live2D/src/ShizukuMain.cpp"
)

xcrun clang++ \
  -std=c++14 \
  -DCSM_TARGET_MAC_GL \
  -DCSM_MINIMUM_DEMO \
  -I"$SDK/Core/include" \
  -I"$SDK/Framework/src" \
  -I"$SDK/Samples/Common" \
  -I"$SDK/Samples/OpenGL/Demo/proj.mac.cmake/src" \
  -I"$SDK/Samples/OpenGL/thirdParty/stb" \
  -I"/opt/homebrew/opt/glew/include" \
  -I"/opt/homebrew/opt/glfw/include" \
  "${FRAMEWORK_SOURCES[@]}" \
  "${COMMON_SOURCES[@]}" \
  "${SAMPLE_SOURCES[@]}" \
  "$SDK/Core/lib/macos/arm64/libLive2DCubismCore.a" \
  /opt/homebrew/opt/glew/lib/libGLEW.dylib \
  /opt/homebrew/opt/glfw/lib/libglfw.dylib \
  -framework OpenGL \
  -framework Cocoa \
  -framework IOKit \
  -framework CoreVideo \
  -o "$BIN"

mkdir -p "$OUT/Resources/shizuku"
cp -R "$ROOT/Assets/shizuku/runtime/." "$OUT/Resources/shizuku/"
cp -R "$SDK/Samples/OpenGL/Shaders/Standard" "$OUT/SampleShaders"
cp -R "$SDK/Framework/src/Rendering/OpenGL/Shaders/Standard" "$OUT/FrameworkShaders"

echo "Built $BIN"
