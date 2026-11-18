// Utils — khai báo forward + helper dùng chung cho Tweak.xm
// (gộp chung một target; Tweak.xm giữ logic chính)
#pragma once
#import <Foundation/Foundation.h>

// box helpers (định nghĩa trong Tweak.xm sau khi il2cpp loaded)
void* boxF(float v);
void* boxB(bool v);
void* boxI(int v);
void* clsFloat(void);
void* clsBool(void);
void* clsInt(void);
void* inv(void* method, void* obj, void** args);
