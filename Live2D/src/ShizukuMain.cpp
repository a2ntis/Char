/**
 * Based on Live2D Cubism Native sample code.
 */

#include <functional>
#include <sstream>
#include <string>
#include <mach-o/dyld.h>
#include <libgen.h>
#include <GL/glew.h>
#include <GLFW/glfw3.h>

#include "LAppDefine.hpp"
#include "LAppAllocator_Common.hpp"
#include "LAppTextureManager.hpp"
#include "LAppPal.hpp"
#include "CubismUserModelExtend.hpp"
#include "MouseActionManager.hpp"

#include <CubismFramework.hpp>

static const Csm::csmChar* kModelDirectoryName = "shizuku";

static Csm::CubismUserModel* gUserModel = nullptr;
static LAppAllocator_Common gCubismAllocator;
static Csm::CubismFramework::Option gCubismOption;
static std::string gExecuteAbsolutePath;
static std::string gCurrentModelDirectory;
static GLFWwindow* gWindow = nullptr;
static int gWindowWidth = 1200;
static int gWindowHeight = 900;

static void InitializeCubism()
{
    gCubismOption.LogFunction = LAppPal::PrintMessageLn;
    gCubismOption.LoggingLevel = Csm::CubismFramework::Option::LogLevel_Verbose;
    gCubismOption.LoadFileFunction = LAppPal::LoadFileAsBytes;
    gCubismOption.ReleaseBytesFunction = LAppPal::ReleaseBytes;
    Csm::CubismFramework::StartUp(&gCubismAllocator, &gCubismOption);
    Csm::CubismFramework::Initialize();
}

static void SetExecuteAbsolutePath()
{
    char path[1024];
    uint32_t size = sizeof(path);
    _NSGetExecutablePath(path, &size);
    gExecuteAbsolutePath = dirname(path);
    gExecuteAbsolutePath += "/";
    LAppPal::SetExecutableAbsolutePath(gExecuteAbsolutePath);
}

static bool InitializeSystem()
{
    if (glfwInit() == GL_FALSE)
    {
        return false;
    }

    glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, 2);
    glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, 1);
    glfwWindowHint(GLFW_OPENGL_FORWARD_COMPAT, GL_TRUE);

    gWindow = glfwCreateWindow(gWindowWidth, gWindowHeight, "Char Shizuku", nullptr, nullptr);
    if (!gWindow)
    {
        glfwTerminate();
        return false;
    }

    glfwMakeContextCurrent(gWindow);
    glfwSwapInterval(1);

    if (glewInit() != GLEW_OK)
    {
        glfwDestroyWindow(gWindow);
        glfwTerminate();
        return false;
    }

    glEnable(GL_BLEND);
    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);

    glfwSetMouseButtonCallback(gWindow, EventHandler::OnMouseCallBack);
    glfwSetCursorPosCallback(gWindow, EventHandler::OnMouseCallBack);
    glfwGetWindowSize(gWindow, &gWindowWidth, &gWindowHeight);

    InitializeCubism();
    MouseActionManager::GetInstance()->Initialize(gWindowWidth, gWindowHeight);
    SetExecuteAbsolutePath();
    return true;
}

static void LoadModel()
{
    gCurrentModelDirectory = gExecuteAbsolutePath + LAppDefine::ResourcesPath + kModelDirectoryName + "/";
    gUserModel = new CubismUserModelExtend(kModelDirectoryName, gCurrentModelDirectory);
    static_cast<CubismUserModelExtend*>(gUserModel)->LoadAssets("shizuku.model3.json", gWindowWidth, gWindowHeight);
    MouseActionManager::GetInstance()->SetUserModel(gUserModel);
}

static void ReleaseAll()
{
    if (gUserModel)
    {
        gUserModel->DeleteRenderer();
        delete gUserModel;
        gUserModel = nullptr;
    }

    glfwDestroyWindow(gWindow);
    glfwTerminate();
    MouseActionManager::ReleaseInstance();
    Csm::CubismFramework::Dispose();
}

static void Run()
{
    while (glfwWindowShouldClose(gWindow) == GL_FALSE)
    {
        int width = 0;
        int height = 0;
        float scaleWidth = 1.0f;
        float scaleHeight = 1.0f;

        glfwGetFramebufferSize(gWindow, &width, &height);
        glfwGetWindowContentScale(gWindow, &scaleWidth, &scaleHeight);
        if (scaleWidth == 0.0f) scaleWidth = 1.0f;
        if (scaleHeight == 0.0f) scaleHeight = 1.0f;

        if ((gWindowWidth != width || gWindowHeight != height) && width > 0 && height > 0)
        {
            MouseActionManager::GetInstance()->ViewInitialize(width / scaleWidth, height / scaleHeight);
            gUserModel->SetRenderTargetSize(width, height);
            gWindowWidth = width;
            gWindowHeight = height;
        }

        LAppPal::UpdateTime();

        glViewport(0, 0, width, height);
        glClearColor(0.0f, 0.0f, 0.0f, 0.0f);
        glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
        glClearDepth(1.0);

        static_cast<CubismUserModelExtend*>(gUserModel)->ModelOnUpdate(gWindow);

        glfwSwapBuffers(gWindow);
        glfwPollEvents();
    }
}

int main(int argc, char** argv)
{
    if (!InitializeSystem())
    {
        return 1;
    }

    LoadModel();
    Run();
    ReleaseAll();
    return 0;
}
