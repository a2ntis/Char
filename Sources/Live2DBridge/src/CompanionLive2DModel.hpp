#pragma once

#include <initializer_list>
#include <string>
#include <vector>

#include "CubismFramework.hpp"
#include "CubismModelSettingJson.hpp"
#include "Id/CubismId.hpp"
#include "Math/CubismMatrix44.hpp"
#include "Model/CubismUserModel.hpp"
#include "Rendering/OpenGL/CubismRenderer_OpenGLES2.hpp"
#include "Type/csmMap.hpp"
#include "Type/csmString.hpp"
#include "Utils/CubismString.hpp"
#include "LAppModel_Common.hpp"
#include "LAppTextureManager.hpp"
#include "LAppView_Common.hpp"

class CompanionLive2DModel : public LAppModel_Common
{
public:
    enum class PresenceState
    {
        Idle = 0,
        Listening = 1,
        Speaking = 2,
        Thinking = 3,
    };

    enum class EmotionState
    {
        Neutral = 0,
        Happy = 1,
        Excited = 2,
        Shy = 3,
        Thinking = 4,
        Sleepy = 5,
        Angry = 6,
    };

    explicit CompanionLive2DModel(const std::string& modelDirectory);
    ~CompanionLive2DModel() override;

    void LoadAssets(const Live2D::Cubism::Framework::csmChar* fileName, Live2D::Cubism::Framework::csmUint32 width, Live2D::Cubism::Framework::csmUint32 height);
    void UpdateAndDraw(int width, int height, const LAppView_Common* view);
    void SetLookTarget(float x, float y);
    void TriggerTapMotion();
    void SetPassiveIdle(bool passiveIdle);
    void SetPresenceState(PresenceState state);
    void SetEmotionState(EmotionState state);
    void SetDragActive(bool dragging);
    void SetManualEmotionPreview(bool enabled);
    void AddExpressionFile(const std::string& name, const std::string& absolutePath);
    void SetEmotionExpressionHints(EmotionState state, const std::vector<std::string>& hints);
    bool TriggerExpressionHints(const std::vector<std::string>& hints);
    bool TriggerMotionGroup(const std::string& groupName);
    Live2D::Cubism::Framework::csmFloat32 GetContentAspectRatio() const;

private:
    void ApplyPresenceState();
    void TryStartExpression(const char* preferredName, const char* fallbackName = nullptr);
    bool StartExpressionByExactName(const std::string& name);
    bool TryStartExpressionMatching(std::initializer_list<const char*> hints);
    bool TryStartExpressionMatching(const std::vector<std::string>& hints);
    bool HasMotionGroup(const Live2D::Cubism::Framework::csmChar* group) const;
    Live2D::Cubism::Framework::CubismMotionQueueEntryHandle StartRandomMotionFromGroups(std::initializer_list<const char*> groups, Live2D::Cubism::Framework::csmInt32 priority);
    void TriggerEmotionMotion();
    void SetupModel(Live2D::Cubism::Framework::csmUint32 width, Live2D::Cubism::Framework::csmUint32 height);
    void SetupTextures();
    void PreloadMotionGroup(const Live2D::Cubism::Framework::csmChar* group);
    void ReleaseModelSetting();
    Live2D::Cubism::Framework::CubismMotionQueueEntryHandle StartMotion(const Live2D::Cubism::Framework::csmChar* group, Live2D::Cubism::Framework::csmInt32 no, Live2D::Cubism::Framework::csmInt32 priority);
    Live2D::Cubism::Framework::CubismMotionQueueEntryHandle StartRandomMotion(const Live2D::Cubism::Framework::csmChar* group, Live2D::Cubism::Framework::csmInt32 priority);
    void UpdateParameters();
    void Draw(Live2D::Cubism::Framework::CubismMatrix44& matrix);

    std::string _modelDirectory;
    Live2D::Cubism::Framework::CubismModelSettingJson* _modelJson;
    LAppTextureManager* _textureManager;
    Live2D::Cubism::Framework::csmMap<Live2D::Cubism::Framework::csmString, Live2D::Cubism::Framework::ACubismMotion*> _motions;
    Live2D::Cubism::Framework::csmMap<Live2D::Cubism::Framework::csmString, Live2D::Cubism::Framework::ACubismMotion*> _expressions;
    Live2D::Cubism::Framework::csmVector<Live2D::Cubism::Framework::CubismIdHandle> _eyeBlinkIds;
    Live2D::Cubism::Framework::csmVector<Live2D::Cubism::Framework::CubismIdHandle> _lipSyncIds;
    const Live2D::Cubism::Framework::CubismId* _idParamAngleX;
    const Live2D::Cubism::Framework::CubismId* _idParamAngleY;
    const Live2D::Cubism::Framework::CubismId* _idParamAngleZ;
    const Live2D::Cubism::Framework::CubismId* _idParamBodyAngleX;
    const Live2D::Cubism::Framework::CubismId* _idParamEyeBallX;
    const Live2D::Cubism::Framework::CubismId* _idParamEyeBallY;
    Live2D::Cubism::Framework::csmFloat32 _userTimeSeconds;
    Live2D::Cubism::Framework::csmBool _motionUpdated;
    Live2D::Cubism::Framework::csmBool _usingFallbackLayout;
    Live2D::Cubism::Framework::csmBool _fallbackLayoutCalibrated;
    Live2D::Cubism::Framework::csmBool _passiveIdle;
    Live2D::Cubism::Framework::csmBool _isDragging;
    Live2D::Cubism::Framework::csmBool _manualEmotionPreview;
    Live2D::Cubism::Framework::csmFloat32 _contentAspectRatio;
    Live2D::Cubism::Framework::csmFloat32 _contentMinX;
    Live2D::Cubism::Framework::csmFloat32 _contentMinY;
    Live2D::Cubism::Framework::csmFloat32 _contentMaxX;
    Live2D::Cubism::Framework::csmFloat32 _contentMaxY;
    Live2D::Cubism::Framework::csmInt32 _lastLayoutWidth;
    Live2D::Cubism::Framework::csmInt32 _lastLayoutHeight;
    PresenceState _presenceState;
    PresenceState _appliedPresenceState;
    EmotionState _emotionState;
    EmotionState _appliedEmotionState;
    bool _hasExpressionUpdater;
    std::vector<std::string> _neutralEmotionHints;
    std::vector<std::string> _happyEmotionHints;
    std::vector<std::string> _excitedEmotionHints;
    std::vector<std::string> _shyEmotionHints;
    std::vector<std::string> _thinkingEmotionHints;
    std::vector<std::string> _sleepyEmotionHints;
    std::vector<std::string> _angryEmotionHints;
};
