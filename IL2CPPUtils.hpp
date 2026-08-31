#pragma once
#include <dlfcn.h>
#include <string>
#include <vector>
#include <iostream>

typedef void* Il2CppDomain;
typedef void* Il2CppAssembly;
typedef void* Il2CppImage;
typedef void* Il2CppClass;
typedef void* MethodInfo;
typedef void* Il2CppObject;
typedef void* Il2CppType;
typedef void* Il2CppThread;

// Runtime arrays in memory
struct Il2CppArray {
    Il2CppObject* obj;
    void* bounds;
    uint32_t max_length;
    void* vector[32]; 
};

// C-APIs
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
        #define RESOLVE(name) name = (name##_t)dlsym(handle, "il2cpp_" #name); if(!name) return false;
        
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
        return true;
    }

    // Globally search for a class across all loaded DLLs
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

    // Calls UnityEngine.Object.FindObjectsOfType(Type) internally to get all instances
    inline std::vector<void*> FindInstances(Il2CppClass* targetClass) {
        std::vector<void*> instances;
        if (!targetClass) return instances;

        Il2CppClass* unityObjClass = FindClassGlobal("Object"); // UnityEngine.Object
        if (!unityObjClass) return instances;

        MethodInfo* findMethod = class_get_method_from_name(unityObjClass, "FindObjectsOfType", 1);
        if (!findMethod) return instances;

        Il2CppObject* typeObj = type_get_object(class_get_type(targetClass));
        void* args[1] = { typeObj };
        
        Il2CppArray* arr = (Il2CppArray*)runtime_invoke(findMethod, nullptr, args, nullptr);
        if (arr) {
            for (uint32_t i = 0; i < arr->max_length; i++) {
                instances.push_back(arr->vector[i]);
            }
        }
        return instances;
    }
}
