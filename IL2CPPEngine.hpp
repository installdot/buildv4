#pragma once
#include <dlfcn.h>
#include <string>
#include <vector>

// --- Memory Layouts ---
struct Il2CppObject_Layout {
    void* klass;   
    void* monitor; 
}; 

struct Il2CppArray {
    Il2CppObject_Layout obj; 
    void* bounds;            
    uintptr_t max_length;    
    void* vector[1];         
};

// --- C-APIs ---
typedef void* Il2CppDomain;
typedef void* Il2CppAssembly;
typedef void* Il2CppImage;
typedef void* Il2CppClass;
typedef void* MethodInfo;
typedef void* FieldInfo;
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
typedef MethodInfo* (*il2cpp_class_get_methods_t)(Il2CppClass* klass, void** iter);
typedef const char* (*il2cpp_method_get_name_t)(const MethodInfo* method);
typedef uint32_t (*il2cpp_method_get_param_count_t)(const MethodInfo* method);
typedef FieldInfo* (*il2cpp_class_get_fields_t)(Il2CppClass* klass, void** iter);
typedef const char* (*il2cpp_field_get_name_t)(FieldInfo* field);
typedef size_t (*il2cpp_field_get_offset_t)(FieldInfo* field);
typedef const Il2CppType* (*il2cpp_field_get_type_t)(FieldInfo* field);
typedef MethodInfo* (*il2cpp_class_get_method_from_name_t)(Il2CppClass* klass, const char* name, int argsCount);
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
    inline il2cpp_class_get_methods_t class_get_methods = nullptr;
    inline il2cpp_method_get_name_t method_get_name = nullptr;
    inline il2cpp_method_get_param_count_t method_get_param_count = nullptr;
    inline il2cpp_class_get_fields_t class_get_fields = nullptr;
    inline il2cpp_field_get_name_t field_get_name = nullptr;
    inline il2cpp_field_get_offset_t field_get_offset = nullptr;
    inline il2cpp_field_get_type_t field_get_type = nullptr;
    inline il2cpp_class_get_method_from_name_t class_get_method_from_name = nullptr;
    inline il2cpp_class_get_type_t class_get_type = nullptr;
    inline il2cpp_type_get_object_t type_get_object = nullptr;
    inline il2cpp_runtime_invoke_t runtime_invoke = nullptr;

    inline bool Initialize() {
        void* handle = RTLD_DEFAULT;
        #define RESOLVE(name) name = (il2cpp_##name##_t)dlsym(handle, "il2cpp_" #name); if(!name) return false;
        
        RESOLVE(domain_get); RESOLVE(thread_attach); RESOLVE(domain_get_assemblies);
        RESOLVE(assembly_get_image); RESOLVE(image_get_class_count); RESOLVE(image_get_class);
        RESOLVE(class_get_name); RESOLVE(class_get_namespace); RESOLVE(class_get_methods);
        RESOLVE(method_get_name); RESOLVE(method_get_param_count); RESOLVE(class_get_fields);
        RESOLVE(field_get_name); RESOLVE(field_get_offset); RESOLVE(field_get_type);
        RESOLVE(class_get_method_from_name); RESOLVE(class_get_type); RESOLVE(type_get_object);
        RESOLVE(runtime_invoke);
        #undef RESOLVE
        return true;
    }

    struct ClassDef { std::string fullName; Il2CppClass* klass; };
    struct MethodDef { std::string name; int paramCount; MethodInfo* method; };
    struct FieldDef { std::string name; size_t offset; FieldInfo* field; };

    inline std::vector<ClassDef> GetAllClasses() {
        std::vector<ClassDef> classes;
        size_t assemblyCount = 0;
        const Il2CppAssembly** assemblies = domain_get_assemblies(domain_get(), &assemblyCount);
        for (size_t i = 0; i < assemblyCount; i++) {
            Il2CppImage* img = assembly_get_image(assemblies[i]);
            size_t classCount = image_get_class_count(img);
            for (size_t j = 0; j < classCount; j++) {
                Il2CppClass* klass = image_get_class(img, j);
                if (!klass) continue;
                const char* ns = class_get_namespace(klass);
                const char* name = class_get_name(klass);
                std::string fullName = (ns && ns[0] != '\0') ? std::string(ns) + "." + name : std::string(name);
                classes.push_back({fullName, klass});
            }
        }
        return classes;
    }

    inline std::vector<MethodDef> GetMethods(Il2CppClass* klass) {
        std::vector<MethodDef> methods;
        if (!klass) return methods;
        void* iter = nullptr;
        while (MethodInfo* method = class_get_methods(klass, &iter)) {
            methods.push_back({method_get_name(method), (int)method_get_param_count(method), method});
        }
        return methods;
    }

    inline std::vector<FieldDef> GetFields(Il2CppClass* klass) {
        std::vector<FieldDef> fields;
        if (!klass) return fields;
        void* iter = nullptr;
        while (FieldInfo* field = class_get_fields(klass, &iter)) {
            fields.push_back({field_get_name(field), field_get_offset(field), field});
        }
        return fields;
    }

    inline std::vector<void*> FindInstances(Il2CppClass* targetClass) {
        std::vector<void*> instances;
        if (!targetClass) return instances;

        Il2CppClass* unityObjClass = nullptr;
        size_t ac = 0; const Il2CppAssembly** as = domain_get_assemblies(domain_get(), &ac);
        for (size_t i = 0; i < ac; i++) {
            Il2CppImage* img = assembly_get_image(as[i]);
            size_t cc = image_get_class_count(img);
            for (size_t j = 0; j < cc; j++) {
                Il2CppClass* k = image_get_class(img, j);
                if (k && std::string(class_get_name(k)) == "Object" && std::string(class_get_namespace(k)) == "UnityEngine") {
                    unityObjClass = k; break;
                }
            }
            if(unityObjClass) break;
        }
        if (!unityObjClass) return instances;

        MethodInfo* findMethod = class_get_method_from_name(unityObjClass, "FindObjectsOfType", 1);
        if (!findMethod) return instances;

        Il2CppObject* typeObj = type_get_object(class_get_type(targetClass));
        void* args[1] = { typeObj };
        
        Il2CppArray* arr = (Il2CppArray*)runtime_invoke(findMethod, nullptr, args, nullptr);
        if (arr && arr->max_length < 500000) { 
            for (uintptr_t i = 0; i < arr->max_length; i++) {
                if (arr->vector[i]) instances.push_back(arr->vector[i]);
            }
        }
        return instances;
    }
}
