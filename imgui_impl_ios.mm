// imgui_impl_ios.mm
#include "imgui.h"
#include "imgui_impl_ios.h"
#import <GLKit/GLKit.h>

static GLKView* g_glkView = nil;

bool ImGui_ImplIOS_Init(void* view, void* context) {
    g_glkView = (__bridge GLKView*)view;
    ImGui::CreateContext();
    return true;
}

void ImGui_ImplIOS_NewFrame() {
    ImGuiIO& io = ImGui::GetIO();
    io.DisplaySize = ImVec2(g_glkView.drawableWidth, g_glkView.drawableHeight);
    io.DeltaTime = 1.0f / 60.0f;
}

void ImGui_ImplIOS_RenderDrawData(ImDrawData* draw_data) {
    [g_glkView bindDrawable];
    glViewport(0, 0, (GLsizei)g_glkView.drawableWidth, (GLsizei)g_glkView.drawableHeight);
    glClearColor(0, 0, 0, 0);
    glClear(GL_COLOR_BUFFER_BIT);

    // Your normal ImGui render code here (imgui_impl_opengl3.cpp does this)
    // For simplicity we use the official backend:
    ImGui_ImplOpenGL3_RenderDrawData(draw_data);
}
