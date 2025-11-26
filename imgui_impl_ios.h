// imgui_impl_ios.h
#pragma once
#include "imgui.h"

bool ImGui_ImplIOS_Init(void* view, void* context);
void ImGui_ImplIOS_Shutdown();
void ImGui_ImplIOS_NewFrame();
void ImGui_ImplIOS_RenderDrawData(ImDrawData* draw_data);
