#include "CompanionLive2DModel.hpp"

#include <GL/glew.h>
#include <algorithm>
#include <cctype>
#include <vector>

#include "CubismDefaultParameterId.hpp"
#include "Id/CubismIdManager.hpp"
#include "Motion/CubismBreathUpdater.hpp"
#include "Motion/CubismEyeBlinkUpdater.hpp"
#include "Motion/CubismExpressionMotion.hpp"
#include "Motion/CubismExpressionUpdater.hpp"
#include "Motion/CubismLookUpdater.hpp"
#include "Motion/CubismMotion.hpp"
#include "Motion/CubismPhysicsUpdater.hpp"
#include "Motion/CubismPoseUpdater.hpp"
#include "Rendering/OpenGL/CubismOffscreenManager_OpenGLES2.hpp"
#include "LAppDefine.hpp"
#include "LAppPal.hpp"

using namespace Live2D::Cubism::Framework;
using namespace DefaultParameterId;

CompanionLive2DModel::CompanionLive2DModel(const std::string& modelDirectory)
    : LAppModel_Common()
    , _modelDirectory(modelDirectory)
    , _modelJson(nullptr)
    , _textureManager(new LAppTextureManager())
    , _idParamAngleX(CubismFramework::GetIdManager()->GetId(ParamAngleX))
    , _idParamAngleY(CubismFramework::GetIdManager()->GetId(ParamAngleY))
    , _idParamAngleZ(CubismFramework::GetIdManager()->GetId(ParamAngleZ))
    , _idParamBodyAngleX(CubismFramework::GetIdManager()->GetId(ParamBodyAngleX))
    , _idParamEyeBallX(CubismFramework::GetIdManager()->GetId(ParamEyeBallX))
    , _idParamEyeBallY(CubismFramework::GetIdManager()->GetId(ParamEyeBallY))
    , _userTimeSeconds(0.0f)
    , _motionUpdated(false)
    , _usingFallbackLayout(false)
    , _fallbackLayoutCalibrated(false)
    , _passiveIdle(false)
    , _isDragging(false)
    , _manualEmotionPreview(false)
    , _contentAspectRatio(0.86f)
    , _contentMinX(0.0f)
    , _contentMinY(0.0f)
    , _contentMaxX(0.0f)
    , _contentMaxY(0.0f)
    , _lastLayoutWidth(0)
    , _lastLayoutHeight(0)
    , _presenceState(PresenceState::Idle)
    , _appliedPresenceState(PresenceState::Idle)
    , _emotionState(EmotionState::Neutral)
    , _appliedEmotionState(EmotionState::Neutral)
    , _hasExpressionUpdater(false)
{
}

CompanionLive2DModel::~CompanionLive2DModel()
{
    ReleaseModelSetting();
    delete _textureManager;
}

void CompanionLive2DModel::LoadAssets(const csmChar* fileName, csmUint32 width, csmUint32 height)
{
    csmSizeInt size;
    const csmString path = csmString(_modelDirectory.c_str()) + fileName;
    csmByte* buffer = CreateBuffer(path.GetRawString(), &size);
    _modelJson = new CubismModelSettingJson(buffer, size);
    DeleteBuffer(buffer, path.GetRawString());
    SetupModel(width, height);
}

void CompanionLive2DModel::SetupModel(csmUint32 width, csmUint32 height)
{
    _updating = true;
    _initialized = false;

    csmByte* buffer = nullptr;
    csmSizeInt size = 0;

    if (strcmp(_modelJson->GetModelFileName(), ""))
    {
        csmString path = csmString(_modelDirectory.c_str()) + _modelJson->GetModelFileName();
        buffer = CreateBuffer(path.GetRawString(), &size);
        LoadModel(buffer, size);
        DeleteBuffer(buffer, path.GetRawString());
        if (_model)
        {
            csmFloat32 minX = 9999.0f;
            csmFloat32 minY = 9999.0f;
            csmFloat32 maxX = -9999.0f;
            csmFloat32 maxY = -9999.0f;
            const csmInt32 drawableCount = _model->GetDrawableCount();
            for (csmInt32 drawableIndex = 0; drawableIndex < drawableCount; ++drawableIndex)
            {
                const csmInt32 vertexCount = _model->GetDrawableVertexCount(drawableIndex);
                const csmFloat32* vertices = _model->GetDrawableVertices(drawableIndex);
                for (csmInt32 i = 0; i < vertexCount; ++i)
                {
                    const csmFloat32 vx = vertices[Constant::VertexOffset + i * Constant::VertexStep];
                    const csmFloat32 vy = vertices[Constant::VertexOffset + i * Constant::VertexStep + 1];
                    minX = std::min(minX, vx);
                    minY = std::min(minY, vy);
                    maxX = std::max(maxX, vx);
                    maxY = std::max(maxY, vy);
                }
            }

            const csmFloat32 contentWidth = maxX - minX;
            const csmFloat32 contentHeight = maxY - minY;
            if (contentWidth > 0.0001f && contentHeight > 0.0001f)
            {
                _contentMinX = minX;
                _contentMinY = minY;
                _contentMaxX = maxX;
                _contentMaxY = maxY;
                _contentAspectRatio = std::max(0.45f, std::min(1.8f, contentWidth / contentHeight));
            }
        }
    }

    if (_modelJson->GetExpressionCount() > 0)
    {
        const csmInt32 count = _modelJson->GetExpressionCount();
        for (csmInt32 i = 0; i < count; i++)
        {
            csmString name = _modelJson->GetExpressionName(i);
            csmString path = csmString(_modelDirectory.c_str()) + _modelJson->GetExpressionFileName(i);
            buffer = CreateBuffer(path.GetRawString(), &size);
            ACubismMotion* motion = LoadExpression(buffer, size, name.GetRawString());
            if (motion)
            {
                _expressions[name] = motion;
            }
            DeleteBuffer(buffer, path.GetRawString());
        }
        CubismExpressionUpdater* expression = CSM_NEW CubismExpressionUpdater(*_expressionManager);
        _updateScheduler.AddUpdatableList(expression);
        _hasExpressionUpdater = true;
    }

    if (_modelJson->GetLipSyncParameterCount() > 0)
    {
        const csmInt32 lipSyncCount = _modelJson->GetLipSyncParameterCount();
        for (csmInt32 i = 0; i < lipSyncCount; ++i)
        {
            _lipSyncIds.PushBack(_modelJson->GetLipSyncParameterId(i));
        }
    }

    if (_modelJson->GetEyeBlinkParameterCount() > 0)
    {
        _eyeBlink = CubismEyeBlink::Create(_modelJson);
        for (csmInt32 i = 0; i < _modelJson->GetEyeBlinkParameterCount(); ++i)
        {
            _eyeBlinkIds.PushBack(_modelJson->GetEyeBlinkParameterId(i));
        }

        if (_eyeBlink)
        {
            CubismEyeBlinkUpdater* eyeBlink = CSM_NEW CubismEyeBlinkUpdater(_motionUpdated, *_eyeBlink);
            _updateScheduler.AddUpdatableList(eyeBlink);
        }
    }

    _breath = CubismBreath::Create();
    if (_breath)
    {
        csmVector<CubismBreath::BreathParameterData> breathParameters;
        breathParameters.PushBack(CubismBreath::BreathParameterData(_idParamAngleX, 0.0f, 15.0f, 6.5345f, 0.5f));
        breathParameters.PushBack(CubismBreath::BreathParameterData(_idParamAngleY, 0.0f, 8.0f, 3.5345f, 0.5f));
        breathParameters.PushBack(CubismBreath::BreathParameterData(_idParamAngleZ, 0.0f, 10.0f, 5.5345f, 0.5f));
        breathParameters.PushBack(CubismBreath::BreathParameterData(_idParamBodyAngleX, 0.0f, 4.0f, 15.5345f, 0.5f));
        breathParameters.PushBack(CubismBreath::BreathParameterData(CubismFramework::GetIdManager()->GetId(ParamBreath), 0.5f, 0.5f, 3.2345f, 0.5f));
        _breath->SetParameters(breathParameters);

        CubismBreathUpdater* breath = CSM_NEW CubismBreathUpdater(*_breath);
        _updateScheduler.AddUpdatableList(breath);
    }

    if (strcmp(_modelJson->GetPoseFileName(), ""))
    {
        csmString path = csmString(_modelDirectory.c_str()) + _modelJson->GetPoseFileName();
        buffer = CreateBuffer(path.GetRawString(), &size);
        LoadPose(buffer, size);
        DeleteBuffer(buffer, path.GetRawString());
    }
    if (_pose != nullptr)
    {
        CubismPoseUpdater* pose = CSM_NEW CubismPoseUpdater(*_pose);
        _updateScheduler.AddUpdatableList(pose);
    }

    if (strcmp(_modelJson->GetPhysicsFileName(), ""))
    {
        csmString path = csmString(_modelDirectory.c_str()) + _modelJson->GetPhysicsFileName();
        buffer = CreateBuffer(path.GetRawString(), &size);
        LoadPhysics(buffer, size);
        DeleteBuffer(buffer, path.GetRawString());
    }
    if (_physics != nullptr)
    {
        CubismPhysicsUpdater* physics = CSM_NEW CubismPhysicsUpdater(*_physics);
        _updateScheduler.AddUpdatableList(physics);
    }

    _look = CubismLook::Create();
    csmVector<CubismLook::LookParameterData> lookParameters;
    lookParameters.PushBack(CubismLook::LookParameterData(_idParamAngleX, 30.0f));
    lookParameters.PushBack(CubismLook::LookParameterData(_idParamAngleY, 0.0f, 30.0f));
    lookParameters.PushBack(CubismLook::LookParameterData(_idParamAngleZ, 0.0f, 0.0f, -30.0f));
    lookParameters.PushBack(CubismLook::LookParameterData(_idParamBodyAngleX, 10.0f));
    lookParameters.PushBack(CubismLook::LookParameterData(_idParamEyeBallX, 1.0f));
    lookParameters.PushBack(CubismLook::LookParameterData(_idParamEyeBallY, 0.0f, 1.0f));
    _look->SetParameters(lookParameters);
    CubismLookUpdater* look = CSM_NEW CubismLookUpdater(*_look, *_dragManager);
    _updateScheduler.AddUpdatableList(look);
    _updateScheduler.SortUpdatableList();

    csmMap<csmString, csmFloat32> layout;
    _modelJson->GetLayoutMap(layout);
    _modelMatrix->SetupFromLayout(layout);
    _usingFallbackLayout = (layout.GetSize() == 0);
    _model->SaveParameters();

    for (csmInt32 i = 0; i < _modelJson->GetMotionGroupCount(); i++)
    {
        PreloadMotionGroup(_modelJson->GetMotionGroupName(i));
    }

    _motionManager->StopAllMotions();
    CreateRenderer(width, height);
    SetupTextures();

    _updating = false;
    _initialized = true;
}

void CompanionLive2DModel::PreloadMotionGroup(const csmChar* group)
{
    const csmInt32 count = _modelJson->GetMotionCount(group);
    for (csmInt32 i = 0; i < count; i++)
    {
        csmString name = Utils::CubismString::GetFormatedString("%s_%d", group, i);
        csmString path = csmString(_modelDirectory.c_str()) + _modelJson->GetMotionFileName(group, i);
        csmByte* buffer = nullptr;
        csmSizeInt size = 0;
        buffer = CreateBuffer(path.GetRawString(), &size);
        CubismMotion* motion = static_cast<CubismMotion*>(LoadMotion(buffer, size, name.GetRawString(), nullptr, nullptr, _modelJson, group, i));
        if (motion)
        {
            motion->SetEffectIds(_eyeBlinkIds, _lipSyncIds);
        }
        _motions[name] = motion;
        DeleteBuffer(buffer, path.GetRawString());
    }
}

CubismMotionQueueEntryHandle CompanionLive2DModel::StartMotion(const csmChar* group, csmInt32 no, csmInt32 priority)
{
    if (!(_modelJson->GetMotionCount(group)))
    {
        return InvalidMotionQueueEntryHandleValue;
    }

    if (priority == LAppDefine::PriorityForce)
    {
        _motionManager->SetReservePriority(priority);
    }
    else if (!_motionManager->ReserveMotion(priority))
    {
        return InvalidMotionQueueEntryHandleValue;
    }

    csmString name = Utils::CubismString::GetFormatedString("%s_%d", group, no);
    CubismMotion* motion = static_cast<CubismMotion*>(_motions[name.GetRawString()]);
    if (motion)
    {
        motion->SetEffectIds(_eyeBlinkIds, _lipSyncIds);
    }
    return _motionManager->StartMotionPriority(motion, false, priority);
}

CubismMotionQueueEntryHandle CompanionLive2DModel::StartRandomMotion(const csmChar* group, csmInt32 priority)
{
    const csmInt32 count = _modelJson->GetMotionCount(group);
    if (count <= 0)
    {
        return InvalidMotionQueueEntryHandleValue;
    }

    const csmInt32 no = rand() % count;
    return StartMotion(group, no, priority);
}

bool CompanionLive2DModel::HasMotionGroup(const csmChar* group) const
{
    return _modelJson && _modelJson->GetMotionCount(group) > 0;
}

CubismMotionQueueEntryHandle CompanionLive2DModel::StartRandomMotionFromGroups(std::initializer_list<const char*> groups, csmInt32 priority)
{
    std::vector<const char*> availableGroups;
    for (const char* group : groups)
    {
        if (HasMotionGroup(group))
        {
            availableGroups.push_back(group);
        }
    }

    if (availableGroups.empty())
    {
        return InvalidMotionQueueEntryHandleValue;
    }

    const char* selectedGroup = availableGroups[rand() % availableGroups.size()];
    return StartRandomMotion(selectedGroup, priority);
}

void CompanionLive2DModel::UpdateParameters()
{
    const csmFloat32 deltaTimeSeconds = LAppPal::GetDeltaTime();
    _userTimeSeconds += deltaTimeSeconds;
    _motionUpdated = false;

    _model->LoadParameters();
    if (_motionManager->IsFinished())
    {
        if (!_passiveIdle)
        {
            StartRandomMotion("Idle", LAppDefine::PriorityIdle);
        }
    }
    else
    {
        _motionUpdated = _motionManager->UpdateMotion(_model, deltaTimeSeconds);
    }
    _model->SaveParameters();
    _updateScheduler.OnLateUpdate(_model, deltaTimeSeconds);

    ApplyPresenceState();
    _model->Update();
}

void CompanionLive2DModel::Draw(CubismMatrix44& matrix)
{
    if (!_model)
    {
        return;
    }
    Rendering::CubismOffscreenManager_OpenGLES2::GetInstance()->BeginFrameProcess();
    matrix.MultiplyByMatrix(_modelMatrix);
    GetRenderer<Rendering::CubismRenderer_OpenGLES2>()->SetMvpMatrix(&matrix);
    GetRenderer<Rendering::CubismRenderer_OpenGLES2>()->DrawModel();
    Rendering::CubismOffscreenManager_OpenGLES2::GetInstance()->EndFrameProcess();
}

void CompanionLive2DModel::UpdateAndDraw(int width, int height, const LAppView_Common* view)
{
    CubismMatrix44 projection;
    projection.LoadIdentity();

    if (_model->GetCanvasWidth() > 1.0f && width < height)
    {
        GetModelMatrix()->SetWidth(2.0f);
        projection.Scale(1.0f, static_cast<float>(width) / static_cast<float>(height));
    }
    else
    {
        projection.Scale(static_cast<float>(height) / static_cast<float>(width), 1.0f);
    }

    if (view)
    {
        projection.MultiplyByMatrix(view->GetViewMatrix());
    }

    UpdateParameters();

    if (_usingFallbackLayout && _model && (!_fallbackLayoutCalibrated || _lastLayoutWidth != width || _lastLayoutHeight != height))
    {
        const csmFloat32 projectionScaleX = projection.GetScaleX();
        const csmFloat32 projectionScaleY = projection.GetScaleY();
        csmFloat32 visibleMinX = 9999.0f;
        csmFloat32 visibleMinY = 9999.0f;
        csmFloat32 visibleMaxX = -9999.0f;
        csmFloat32 visibleMaxY = -9999.0f;
        csmInt32 visibleDrawableCount = 0;

        const csmInt32 drawableCount = _model->GetDrawableCount();
        for (csmInt32 drawableIndex = 0; drawableIndex < drawableCount; ++drawableIndex)
        {
            if (!_model->GetDrawableDynamicFlagIsVisible(drawableIndex))
            {
                continue;
            }

            const csmInt32 vertexCount = _model->GetDrawableVertexCount(drawableIndex);
            const csmFloat32* vertices = _model->GetDrawableVertices(drawableIndex);
            if (!vertices || vertexCount <= 0)
            {
                continue;
            }

            visibleDrawableCount += 1;
            for (csmInt32 i = 0; i < vertexCount; ++i)
            {
                const csmFloat32 vx = vertices[Constant::VertexOffset + i * Constant::VertexStep];
                const csmFloat32 vy = vertices[Constant::VertexOffset + i * Constant::VertexStep + 1];
                visibleMinX = std::min(visibleMinX, vx);
                visibleMinY = std::min(visibleMinY, vy);
                visibleMaxX = std::max(visibleMaxX, vx);
                visibleMaxY = std::max(visibleMaxY, vy);
            }
        }

        if (visibleDrawableCount == 0)
        {
            visibleMinX = _contentMinX;
            visibleMinY = _contentMinY;
            visibleMaxX = _contentMaxX;
            visibleMaxY = _contentMaxY;
        }

        const csmFloat32 contentWidth = visibleMaxX - visibleMinX;
        const csmFloat32 contentHeight = visibleMaxY - visibleMinY;
        if (contentWidth > 0.0001f && contentHeight > 0.0001f &&
            std::abs(projectionScaleX) > 0.0001f && std::abs(projectionScaleY) > 0.0001f)
        {
            const csmFloat32 contentCenterX = (visibleMinX + visibleMaxX) * 0.5f;
            const csmFloat32 targetMargin = 0.92f;
            const csmFloat32 availableWidth = (2.0f * targetMargin) / std::abs(projectionScaleX);
            const csmFloat32 availableHeight = (2.0f * targetMargin) / std::abs(projectionScaleY);
            const csmFloat32 scale = std::min(availableWidth / contentWidth, availableHeight / contentHeight);

            const csmFloat32 targetBottom = (-1.0f * targetMargin) / projectionScaleY;
            const csmFloat32 translateX = -contentCenterX * scale;
            const csmFloat32 translateY = targetBottom - (visibleMinY * scale);

            _modelMatrix->LoadIdentity();
            _modelMatrix->Scale(scale, scale);
            _modelMatrix->Translate(translateX, translateY);
        }

        _fallbackLayoutCalibrated = true;
        _lastLayoutWidth = width;
        _lastLayoutHeight = height;
    }

    Draw(projection);
}

csmFloat32 CompanionLive2DModel::GetContentAspectRatio() const
{
    return _contentAspectRatio;
}

void CompanionLive2DModel::SetLookTarget(float x, float y)
{
    SetDragging(x, y);
}

void CompanionLive2DModel::TriggerTapMotion()
{
    StartRandomMotionFromGroups({"Tap", "FlickUp", "Flick", "Flick3"}, LAppDefine::PriorityNormal);
}

void CompanionLive2DModel::SetPassiveIdle(bool passiveIdle)
{
    _passiveIdle = passiveIdle;
}

void CompanionLive2DModel::SetPresenceState(PresenceState state)
{
    _presenceState = state;
}

void CompanionLive2DModel::SetEmotionState(EmotionState state)
{
    _emotionState = state;
}

void CompanionLive2DModel::SetEmotionExpressionHints(EmotionState state, const std::vector<std::string>& hints)
{
    switch (state)
    {
    case EmotionState::Neutral:
        _neutralEmotionHints = hints;
        break;
    case EmotionState::Happy:
        _happyEmotionHints = hints;
        break;
    case EmotionState::Excited:
        _excitedEmotionHints = hints;
        break;
    case EmotionState::Shy:
        _shyEmotionHints = hints;
        break;
    case EmotionState::Thinking:
        _thinkingEmotionHints = hints;
        break;
    case EmotionState::Sleepy:
        _sleepyEmotionHints = hints;
        break;
    case EmotionState::Angry:
        _angryEmotionHints = hints;
        break;
    }
}

void CompanionLive2DModel::AddExpressionFile(const std::string& name, const std::string& absolutePath)
{
    const csmString key(name.c_str());
    if (_expressions.IsExist(key))
    {
        return;
    }

    csmSizeInt size = 0;
    csmByte* buffer = CreateBuffer(absolutePath.c_str(), &size);
    if (!buffer)
    {
        return;
    }

    ACubismMotion* motion = LoadExpression(buffer, size, name.c_str());
    DeleteBuffer(buffer, absolutePath.c_str());
    if (!motion)
    {
        return;
    }

    _expressions[key] = motion;

    if (!_hasExpressionUpdater)
    {
        CubismExpressionUpdater* expression = CSM_NEW CubismExpressionUpdater(*_expressionManager);
        _updateScheduler.AddUpdatableList(expression);
        _updateScheduler.SortUpdatableList();
        _hasExpressionUpdater = true;
    }
}

void CompanionLive2DModel::SetDragActive(bool dragging)
{
    const csmBool wasDragging = _isDragging;
    _isDragging = dragging;

    if (dragging && !wasDragging)
    {
        StartRandomMotionFromGroups({"Flick", "FlickLeft", "FlickRight", "Shake"}, LAppDefine::PriorityNormal);
    }
}

void CompanionLive2DModel::SetManualEmotionPreview(bool enabled)
{
    _manualEmotionPreview = enabled;
}

bool CompanionLive2DModel::TriggerExpressionHints(const std::vector<std::string>& hints)
{
    _manualEmotionPreview = true;

    for (const std::string& hint : hints)
    {
        if (hint.empty())
        {
            continue;
        }

        if (StartExpressionByExactName(hint))
        {
            return true;
        }
    }

    return TryStartExpressionMatching(hints);
}

bool CompanionLive2DModel::TriggerMotionGroup(const std::string& groupName)
{
    if (groupName.empty())
    {
        return false;
    }

    _manualEmotionPreview = true;
    return StartRandomMotion(groupName.c_str(), LAppDefine::PriorityForce) != InvalidMotionQueueEntryHandleValue;
}

void CompanionLive2DModel::TriggerEmotionMotion()
{
    switch (_emotionState)
    {
    case EmotionState::Happy:
        if (!_manualEmotionPreview) StartRandomMotionFromGroups({"Tap", "FlickUp"}, LAppDefine::PriorityNormal);
        break;
    case EmotionState::Excited:
        if (!_manualEmotionPreview) StartRandomMotionFromGroups({"FlickUp", "Tap", "Shake"}, LAppDefine::PriorityNormal);
        break;
    case EmotionState::Shy:
        if (!_manualEmotionPreview) StartRandomMotionFromGroups({"FlickDown", "Flick", "Tap"}, LAppDefine::PriorityNormal);
        break;
    case EmotionState::Thinking:
        if (!_manualEmotionPreview) StartRandomMotionFromGroups({"Flick3", "Shake", "Flick"}, LAppDefine::PriorityNormal);
        break;
    case EmotionState::Sleepy:
        if (!_manualEmotionPreview) StartRandomMotionFromGroups({"FlickDown", "Idle"}, LAppDefine::PriorityNormal);
        break;
    case EmotionState::Angry:
        if (!_manualEmotionPreview) StartRandomMotionFromGroups({"Shake", "Flick", "Tap"}, LAppDefine::PriorityNormal);
        break;
    case EmotionState::Neutral:
        break;
    }
}

void CompanionLive2DModel::ApplyPresenceState()
{
    if (!_model)
    {
        return;
    }

    auto addValueIfPresent = [&](const char* parameterId, csmFloat32 value, csmFloat32 weight) {
        if (!parameterId)
        {
            return;
        }

        const CubismIdHandle id = CubismFramework::GetIdManager()->GetId(parameterId);
        if (_model->GetParameterIndex(id) < 0)
        {
            return;
        }

        _model->AddParameterValue(id, value, weight);
    };

    auto setValueIfPresent = [&](const char* parameterId, csmFloat32 value, csmFloat32 weight) {
        if (!parameterId)
        {
            return;
        }

        const CubismIdHandle id = CubismFramework::GetIdManager()->GetId(parameterId);
        if (_model->GetParameterIndex(id) < 0)
        {
            return;
        }

        _model->SetParameterValue(id, value, weight);
    };

    if (_emotionState != _appliedEmotionState)
    {
        switch (_emotionState)
        {
        case EmotionState::Neutral:
            if (!TryStartExpressionMatching(_neutralEmotionHints))
            {
                TryStartExpression("Normal.exp3.json");
            }
            break;
        case EmotionState::Happy:
            if (!TryStartExpressionMatching(_happyEmotionHints) &&
                !TryStartExpressionMatching({"smile", "happy", "love"}))
            {
                TryStartExpression("Smile.exp3.json", "Happy.exp3.json");
            }
            break;
        case EmotionState::Excited:
            if (!TryStartExpressionMatching(_excitedEmotionHints) &&
                !TryStartExpressionMatching({"excited", "surprised", "shock"}))
            {
                TryStartExpression("Smile.exp3.json", "Surprised.exp3.json");
            }
            break;
        case EmotionState::Shy:
            if (!TryStartExpressionMatching(_shyEmotionHints) &&
                !TryStartExpressionMatching({"blush", "shy", "embarr", "love"}))
            {
                TryStartExpression("Blushing.exp3.json", "Smile.exp3.json");
            }
            break;
        case EmotionState::Thinking:
            if (!TryStartExpressionMatching(_thinkingEmotionHints) &&
                !TryStartExpressionMatching({"normal", "idle", "think"}))
            {
                TryStartExpression("Normal.exp3.json");
            }
            break;
        case EmotionState::Sleepy:
            if (!TryStartExpressionMatching(_sleepyEmotionHints) &&
                !TryStartExpressionMatching({"sad", "normal"}))
            {
                TryStartExpression("Normal.exp3.json");
            }
            break;
        case EmotionState::Angry:
            if (!TryStartExpressionMatching(_angryEmotionHints) &&
                !TryStartExpressionMatching({"angry", "pout", "mad"}))
            {
                TryStartExpression("Angry.exp3.json", "Sad.exp3.json");
            }
            break;
        }

        TriggerEmotionMotion();
        _appliedEmotionState = _emotionState;
    }

    if (!_manualEmotionPreview && _presenceState != _appliedPresenceState)
    {
        switch (_presenceState)
        {
        case PresenceState::Idle:
            break;
        case PresenceState::Listening:
            if (_emotionState == EmotionState::Neutral)
            {
                TryStartExpression("Surprised.exp3.json", "Blushing.exp3.json");
            }
            break;
        case PresenceState::Speaking:
            if (_emotionState == EmotionState::Neutral)
            {
                TryStartExpression("Smile.exp3.json", "Normal.exp3.json");
            }
            break;
        case PresenceState::Thinking:
            if (_emotionState == EmotionState::Neutral)
            {
                TryStartExpression("Normal.exp3.json");
            }
            StartRandomMotionFromGroups({"Flick3", "Flick", "Idle"}, LAppDefine::PriorityNormal);
            break;
        }
        _appliedPresenceState = _presenceState;
    }

    if (_presenceState == PresenceState::Listening)
    {
        const csmFloat32 pulse = 0.5f + 0.5f * sinf(_userTimeSeconds * 4.0f);
        addValueIfPresent("PARAM_ANGLE_X", 6.0f * sinf(_userTimeSeconds * 2.8f), 0.55f);
        addValueIfPresent("ParamAngleX", 6.0f * sinf(_userTimeSeconds * 2.8f), 0.55f);
        addValueIfPresent("PARAM_ANGLE_Y", 10.0f * pulse, 0.6f);
        addValueIfPresent("ParamAngleY", 10.0f * pulse, 0.6f);
        addValueIfPresent("PARAM_BODY_ANGLE_X", 6.0f * sinf(_userTimeSeconds * 2.5f), 0.45f);
        addValueIfPresent("PARAM_BODY_X", 6.0f * sinf(_userTimeSeconds * 2.5f), 0.45f);
        addValueIfPresent("ParamBodyAngleX", 6.0f * sinf(_userTimeSeconds * 2.5f), 0.45f);
        addValueIfPresent("PARAM_BREATH", 0.45f + 0.25f * pulse, 0.5f);
        addValueIfPresent("ParamBreath", 0.45f + 0.25f * pulse, 0.5f);
    }
    else if (_presenceState == PresenceState::Speaking)
    {
        const csmFloat32 mouthValue = 0.35f + 0.45f * (0.5f + 0.5f * sinf(_userTimeSeconds * 14.0f));
        for (csmUint32 i = 0; i < _lipSyncIds.GetSize(); ++i)
        {
            _model->SetParameterValue(_lipSyncIds[i], mouthValue, 0.9f);
        }

        addValueIfPresent("PARAM_ANGLE_X", 8.0f * sinf(_userTimeSeconds * 3.8f), 0.5f);
        addValueIfPresent("ParamAngleX", 8.0f * sinf(_userTimeSeconds * 3.8f), 0.5f);
        addValueIfPresent("PARAM_ANGLE_Y", 4.0f * sinf(_userTimeSeconds * 5.2f), 0.45f);
        addValueIfPresent("ParamAngleY", 4.0f * sinf(_userTimeSeconds * 5.2f), 0.45f);
        addValueIfPresent("PARAM_BODY_ANGLE_X", 7.0f * sinf(_userTimeSeconds * 2.2f), 0.5f);
        addValueIfPresent("PARAM_BODY_X", 7.0f * sinf(_userTimeSeconds * 2.2f), 0.5f);
        addValueIfPresent("ParamBodyAngleX", 7.0f * sinf(_userTimeSeconds * 2.2f), 0.5f);
        addValueIfPresent("PARAM_BODY_ANGLE_Z", 3.0f * sinf(_userTimeSeconds * 3.1f), 0.35f);
        addValueIfPresent("PARAM_BODY_Z", 3.0f * sinf(_userTimeSeconds * 3.1f), 0.35f);
        addValueIfPresent("ParamBodyAngleZ", 3.0f * sinf(_userTimeSeconds * 3.1f), 0.35f);
        addValueIfPresent("PARAM_BREATH", 0.7f, 0.5f);
        addValueIfPresent("ParamBreath", 0.7f, 0.5f);
        setValueIfPresent("PARAM_MOUTH_FORM", 0.35f, 0.35f);
        setValueIfPresent("ParamMouthForm", 0.35f, 0.35f);
    }
    else if (_presenceState == PresenceState::Thinking)
    {
        const csmFloat32 ponder = 0.5f + 0.5f * sinf(_userTimeSeconds * 1.8f);
        addValueIfPresent("PARAM_ANGLE_X", 5.0f * sinf(_userTimeSeconds * 1.2f), 0.35f);
        addValueIfPresent("ParamAngleX", 5.0f * sinf(_userTimeSeconds * 1.2f), 0.35f);
        addValueIfPresent("PARAM_ANGLE_Y", 6.0f + 2.0f * ponder, 0.35f);
        addValueIfPresent("ParamAngleY", 6.0f + 2.0f * ponder, 0.35f);
        addValueIfPresent("PARAM_BODY_ANGLE_X", 4.0f * sinf(_userTimeSeconds * 0.9f), 0.24f);
        addValueIfPresent("PARAM_BODY_X", 4.0f * sinf(_userTimeSeconds * 0.9f), 0.24f);
        addValueIfPresent("ParamBodyAngleX", 4.0f * sinf(_userTimeSeconds * 0.9f), 0.24f);
        addValueIfPresent("PARAM_EYE_BALL_X", 0.22f * sinf(_userTimeSeconds * 0.7f), 0.3f);
        addValueIfPresent("ParamEyeBallX", 0.22f * sinf(_userTimeSeconds * 0.7f), 0.3f);
        addValueIfPresent("PARAM_EYE_BALL_Y", -0.18f, 0.28f);
        addValueIfPresent("ParamEyeBallY", -0.18f, 0.28f);
        addValueIfPresent("PARAM_BREATH", 0.42f + 0.18f * ponder, 0.35f);
        addValueIfPresent("ParamBreath", 0.42f + 0.18f * ponder, 0.35f);
        setValueIfPresent("PARAM_MOUTH_FORM", -0.15f, 0.28f);
        setValueIfPresent("ParamMouthForm", -0.15f, 0.28f);
    }
    else
    {
        const csmFloat32 sway = sinf(_userTimeSeconds * 1.6f);
        const csmFloat32 breathe = 0.5f + 0.5f * sinf(_userTimeSeconds * 2.1f);
        addValueIfPresent("PARAM_ANGLE_X", 4.5f * sway, 0.55f);
        addValueIfPresent("ParamAngleX", 4.5f * sway, 0.55f);
        addValueIfPresent("PARAM_ANGLE_Y", 2.4f * sinf(_userTimeSeconds * 1.1f), 0.45f);
        addValueIfPresent("ParamAngleY", 2.4f * sinf(_userTimeSeconds * 1.1f), 0.45f);
        addValueIfPresent("PARAM_BODY_ANGLE_X", 8.0f * sway, 0.5f);
        addValueIfPresent("PARAM_BODY_X", 8.0f * sway, 0.5f);
        addValueIfPresent("ParamBodyAngleX", 8.0f * sway, 0.5f);
        addValueIfPresent("PARAM_BODY_ANGLE_Z", 4.0f * sinf(_userTimeSeconds * 0.9f), 0.35f);
        addValueIfPresent("PARAM_BODY_Z", 4.0f * sinf(_userTimeSeconds * 0.9f), 0.35f);
        addValueIfPresent("ParamBodyAngleZ", 4.0f * sinf(_userTimeSeconds * 0.9f), 0.35f);
        addValueIfPresent("PARAM_EYE_BALL_X", 0.3f * sinf(_userTimeSeconds * 0.7f), 0.42f);
        addValueIfPresent("ParamEyeBallX", 0.3f * sinf(_userTimeSeconds * 0.7f), 0.42f);
        addValueIfPresent("PARAM_EYE_BALL_Y", 0.14f * (breathe - 0.5f), 0.34f);
        addValueIfPresent("ParamEyeBallY", 0.14f * (breathe - 0.5f), 0.34f);
        addValueIfPresent("PARAM_BREATH", 0.5f + 0.35f * breathe, 0.6f);
        addValueIfPresent("ParamBreath", 0.5f + 0.35f * breathe, 0.6f);
    }

    switch (_emotionState)
    {
    case EmotionState::Happy:
        addValueIfPresent("PARAM_ANGLE_Z", 6.0f * sinf(_userTimeSeconds * 2.1f), 0.22f);
        addValueIfPresent("ParamAngleZ", 6.0f * sinf(_userTimeSeconds * 2.1f), 0.22f);
        setValueIfPresent("PARAM_MOUTH_FORM", 0.45f, 0.35f);
        setValueIfPresent("ParamMouthForm", 0.45f, 0.35f);
        break;
    case EmotionState::Excited:
        addValueIfPresent("PARAM_ANGLE_X", 8.0f * sinf(_userTimeSeconds * 4.0f), 0.25f);
        addValueIfPresent("ParamAngleX", 8.0f * sinf(_userTimeSeconds * 4.0f), 0.25f);
        addValueIfPresent("PARAM_BODY_ANGLE_X", 10.0f * sinf(_userTimeSeconds * 3.4f), 0.2f);
        addValueIfPresent("PARAM_BODY_X", 10.0f * sinf(_userTimeSeconds * 3.4f), 0.2f);
        addValueIfPresent("ParamBodyAngleX", 10.0f * sinf(_userTimeSeconds * 3.4f), 0.2f);
        setValueIfPresent("PARAM_MOUTH_FORM", 0.6f, 0.32f);
        setValueIfPresent("ParamMouthForm", 0.6f, 0.32f);
        break;
    case EmotionState::Shy:
        addValueIfPresent("PARAM_ANGLE_X", -5.0f, 0.2f);
        addValueIfPresent("ParamAngleX", -5.0f, 0.2f);
        addValueIfPresent("PARAM_ANGLE_Y", -3.0f, 0.18f);
        addValueIfPresent("ParamAngleY", -3.0f, 0.18f);
        addValueIfPresent("PARAM_EYE_BALL_Y", -0.22f, 0.26f);
        addValueIfPresent("ParamEyeBallY", -0.22f, 0.26f);
        setValueIfPresent("PARAM_MOUTH_FORM", 0.1f, 0.2f);
        setValueIfPresent("ParamMouthForm", 0.1f, 0.2f);
        break;
    case EmotionState::Thinking:
        addValueIfPresent("PARAM_EYE_BALL_X", -0.18f, 0.2f);
        addValueIfPresent("ParamEyeBallX", -0.18f, 0.2f);
        setValueIfPresent("PARAM_MOUTH_FORM", -0.25f, 0.18f);
        setValueIfPresent("ParamMouthForm", -0.25f, 0.18f);
        break;
    case EmotionState::Sleepy:
        addValueIfPresent("PARAM_ANGLE_Y", -6.0f, 0.22f);
        addValueIfPresent("ParamAngleY", -6.0f, 0.22f);
        addValueIfPresent("PARAM_EYE_BALL_Y", -0.3f, 0.18f);
        addValueIfPresent("ParamEyeBallY", -0.3f, 0.18f);
        setValueIfPresent("PARAM_MOUTH_FORM", -0.1f, 0.18f);
        setValueIfPresent("ParamMouthForm", -0.1f, 0.18f);
        break;
    case EmotionState::Angry:
        addValueIfPresent("PARAM_ANGLE_X", 6.0f, 0.2f);
        addValueIfPresent("ParamAngleX", 6.0f, 0.2f);
        addValueIfPresent("PARAM_ANGLE_Y", 2.0f, 0.16f);
        addValueIfPresent("ParamAngleY", 2.0f, 0.16f);
        setValueIfPresent("PARAM_MOUTH_FORM", -0.5f, 0.28f);
        setValueIfPresent("ParamMouthForm", -0.5f, 0.28f);
        break;
    case EmotionState::Neutral:
        break;
    }

    if (_isDragging)
    {
        addValueIfPresent("PARAM_ANGLE_X", 12.0f * sinf(_userTimeSeconds * 5.0f), 0.45f);
        addValueIfPresent("ParamAngleX", 12.0f * sinf(_userTimeSeconds * 5.0f), 0.45f);
        addValueIfPresent("PARAM_BODY_ANGLE_X", 15.0f * sinf(_userTimeSeconds * 4.2f), 0.4f);
        addValueIfPresent("PARAM_BODY_X", 15.0f * sinf(_userTimeSeconds * 4.2f), 0.4f);
        addValueIfPresent("ParamBodyAngleX", 15.0f * sinf(_userTimeSeconds * 4.2f), 0.4f);
        addValueIfPresent("PARAM_ANGLE_Y", 4.0f, 0.22f);
        addValueIfPresent("ParamAngleY", 4.0f, 0.22f);
    }
}

void CompanionLive2DModel::TryStartExpression(const char* preferredName, const char* fallbackName)
{
    auto startIfAvailable = [&](const char* expressionName) -> bool {
        if (!expressionName)
        {
            return false;
        }

        return StartExpressionByExactName(expressionName);
    };

    if (startIfAvailable(preferredName))
    {
        return;
    }

    startIfAvailable(fallbackName);
}

bool CompanionLive2DModel::StartExpressionByExactName(const std::string& name)
{
    if (name.empty())
    {
        return false;
    }

    const csmString directKey(name.c_str());
    if (_expressions.IsExist(directKey))
    {
        ACubismMotion* motion = _expressions[directKey];
        if (motion)
        {
            _expressionManager->StartMotion(motion, false);
            return true;
        }
    }

    auto normalize = [](std::string value) {
        std::transform(value.begin(), value.end(), value.begin(), [](unsigned char c) {
            return static_cast<char>(std::tolower(c));
        });
        return value;
    };

    const std::string normalizedTarget = normalize(name);
    for (auto iter = _expressions.Begin(); iter != _expressions.End(); ++iter)
    {
        std::string expressionName = normalize(iter->First.GetRawString());
        if (expressionName != normalizedTarget)
        {
            continue;
        }

        ACubismMotion* motion = iter->Second;
        if (!motion)
        {
            continue;
        }

        _expressionManager->StartMotion(motion, false);
        return true;
    }

    return false;
}

bool CompanionLive2DModel::TryStartExpressionMatching(std::initializer_list<const char*> hints)
{
    auto normalize = [](std::string value) {
        std::transform(value.begin(), value.end(), value.begin(), [](unsigned char c) {
            return static_cast<char>(std::tolower(c));
        });
        return value;
    };

    for (const char* hint : hints)
    {
        if (!hint)
        {
            continue;
        }

        const std::string normalizedHint = normalize(hint);
        for (auto iter = _expressions.Begin(); iter != _expressions.End(); ++iter)
        {
            std::string expressionName = iter->First.GetRawString();
            expressionName = normalize(expressionName);
            if (expressionName.find(normalizedHint) == std::string::npos)
            {
                continue;
            }

            ACubismMotion* motion = iter->Second;
            if (!motion)
            {
                continue;
            }

            _expressionManager->StartMotion(motion, false);
            return true;
        }
    }

    return false;
}

bool CompanionLive2DModel::TryStartExpressionMatching(const std::vector<std::string>& hints)
{
    for (const std::string& hint : hints)
    {
        if (hint.empty())
        {
            continue;
        }

        if (TryStartExpressionMatching({hint.c_str()}))
        {
            return true;
        }
    }

    return false;
}

void CompanionLive2DModel::SetupTextures()
{
    for (csmInt32 index = 0; index < _modelJson->GetTextureCount(); index++)
    {
        if (!strcmp(_modelJson->GetTextureFileName(index), ""))
        {
            continue;
        }
        csmString texturePath = csmString(_modelDirectory.c_str()) + _modelJson->GetTextureFileName(index);
        auto* texture = _textureManager->CreateTextureFromPngFile(texturePath.GetRawString());
        GetRenderer<Rendering::CubismRenderer_OpenGLES2>()->BindTexture(index, texture->id);
    }
    GetRenderer<Rendering::CubismRenderer_OpenGLES2>()->IsPremultipliedAlpha(false);
}

void CompanionLive2DModel::ReleaseModelSetting()
{
    for (auto iter = _motions.Begin(); iter != _motions.End(); ++iter)
    {
        ACubismMotion::Delete(iter->Second);
    }
    _motions.Clear();
    for (auto iter = _expressions.Begin(); iter != _expressions.End(); ++iter)
    {
        ACubismMotion::Delete(iter->Second);
    }
    _expressions.Clear();
    delete _modelJson;
    _modelJson = nullptr;
    Rendering::CubismOffscreenManager_OpenGLES2::ReleaseInstance();
}
