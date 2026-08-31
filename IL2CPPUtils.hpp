#pragma once
#include <dlfcn.h>
#include <string>
#include <vector>
#include <iostream>

// --- Corrected Memory Layouts ---
struct Il2CppObject_Layout {
    void* klass;   // 8 bytes on 64-bit
    void* monitor; // 8 bytes on 64-bit
}; // Total: 16 bytes

struct Il2CppArray {
    Il2CppObject_Layout obj; // Embedded struct, NOT a pointer (16 bytes)
    void* bounds;            // 8 bytes
    uintptr_t max_length;    // 8 bytes (Use uintptr_t for 64-bit safety)
    void* vector[1];         // Start of element pointers
};

// C-APIs
typedef void* Il2CppDomain;
typedef void* Il2CppAssembly;
typedef void* Il2CppImage;
typedef void* Il2CppClass;
typedef void* MethodInfo;
typedef void* Il2CppObject;
typedef void* Il2CppType;
typedef void* Il2CppThread;

typedef Il2CppDomain* (*il2cpp_domain_get_t)();
typedef Il2CppThread* (*il2cpp_thread_attach_t)(Il2CppDomain* domain);
typedef const Il2CppAssembly** (*il2cpp_domain_get_assemblies_t)(const Il2CppDomain* domain, size_t* size);
typedef Il2CppImage* (*il2cpp_assembly_get_image_t)(const Il2CppAssembly* assembly);
typedef size_t (*il2cpp_image_get_class_count_t)(const Il2CppImage* image);
typedef Il2CppClass* (*il2cpp_image_get_class_t)(const Il2CppImage* image, size_t index);
typedef const char* (*il2cpp_class_get_name_t)(Il2CppClass* klass);
typedef const char* (*il2cpp_class_get_namespace_t)(Il2CppClass* klass);
typedef MethodInfo* (*il2cpp_class_get_method_from_name_t)(Il2CppClass* klass, const char* name, int argsCount);
typedef MethodInfo* (*il2cpp_class_get_methods_t)(Il2CppClass* klass, void** iter);
typedef const char* (*il2cpp_method_get_name_t)(const MethodInfo* method);
typedef uint32_t (*il2cpp_method_get_param_count_t)(const MethodInfo* method);
typedef const Il2CppType* (*il2cpp_class_get_type_t)(Il2CppClass* klass);
typedef Il2CppObject* (*il2cpp_type_get_object_t)(const Il2CppType* type);
typedef Il2CppObject* (*il2cpp_runtime_invoke_t)(MethodInfo* method, void* obj, void** params, Il2CppObject** exc);

namespace IL2CPP {
    inline il2cpp_domain_get_t domain_get = nullptr;
    inline il2cpp_thread_attach_t thread_attach = nullptr;
    inline il2cpp_domain_get_assemblies_t domain_get_assemblies = nullptr;
    inline il2cpp_assembly_get_image_t assembly_get_image = nullptr;
    inline il2cpp_image_get_class_count_t image_get_class_count = nullptr;
    inline il2cpp_image_get_class_t image_get_class = nullptr;
    inline il2cpp_class_get_name_t class_get_name = nullptr;
    inline il2cpp_class_get_namespace_t class_get_namespace = nullptr;
    inline il2cpp_class_get_method_from_name_t class_get_method_from_name = nullptr;
    inline il2cpp_class_get_methods_t class_get_methods = nullptr;
    inline il2cpp_method_get_name_t method_get_name = nullptr;
    inline il2cpp_method_get_param_count_t method_get_param_count = nullptr;
    inline il2cpp_class_get_type_t class_get_type = nullptr;
    inline il2cpp_type_get_object_t type_get_object = nullptr;
    inline il2cpp_runtime_invoke_t runtime_invoke = nullptr;

    inline bool Initialize() {
        void* handle = RTLD_DEFAULT;
        
        #define RESOLVE(name) name = (il2cpp_##name##_t)dlsym(handle, "il2cpp_" #name); if(!name) return false;
        
        RESOLVE(domain_get);
        RESOLVE(thread_attach);
        RESOLVE(domain_get_assemblies);
        RESOLVE(assembly_get_image);
        RESOLVE(image_get_class_count);
        RESOLVE(image_get_class);
        RESOLVE(class_get_name);
        RESOLVE(class_get_namespace);
        RESOLVE(class_get_method_from_name);
        RESOLVE(class_get_methods);
        RESOLVE(method_get_name);
        RESOLVE(method_get_param_count);
        RESOLVE(class_get_type);
        RESOLVE(type_get_object);
        RESOLVE(runtime_invoke);
        
        #undef RESOLVE
        return true;
    }

    inline Il2CppClass* FindClassGlobal(const std::string& className) {
        size_t assemblyCount = 0;
        const Il2CppAssembly** assemblies = domain_get_assemblies(domain_get(), &assemblyCount);
        for (size_t i = 0; i < assemblyCount; i++) {
            Il2CppImage* img = assembly_get_image(assemblies[i]);
            size_t classCount = image_get_class_count(img);
            for (size_t j = 0; j < classCount; j++) {
                Il2CppClass* klass = image_get_class(img, j);
                if (klass && className == class_get_name(klass)) {
                    return klass;
                }
            }
        }
        return nullptr;
    }

    inline std::vector<void*> FindInstances(Il2CppClass* targetClass) {
        std::vector<void*> instances;
        if (!targetClass) return instances;

        Il2CppClass* unityObjClass = FindClassGlobal("Object"); 
        if (!unityObjClass) return instances;

        MethodInfo* findMethod = class_get_method_from_name(unityObjClass, "FindObjectsOfType", 1);
        if (!findMethod) return instances;

        Il2CppObject* typeObj = type_get_object(class_get_type(targetClass));
        void* args[1] = { typeObj };
        
        Il2CppArray* arr = (Il2CppArray*)runtime_invoke(findMethod, nullptr, args, nullptr);
        if (arr) {
            // Crash-safety sanity bounds check
            uintptr_t array_length = arr->max_length;
            if (array_length > 500000) { 
                // If it reads an absurd number, bail out instead of crashing
                std::cout << "[IL2CPP] Array length sanity check failed! Length: " << array_length << std::endl;
                return instances; 
            }

            for (uintptr_t i = 0; i < array_length; i++) {
                if (arr->vector[i]) {
                    instances.push_back(arr->vector[i]);
                }
            }
        }
        return instances;
    }
}
