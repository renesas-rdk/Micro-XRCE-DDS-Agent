# examples/custom_agent/CMakeLists.txt
add_executable(CustomXRCEAgent
    custom_agent.cpp
    helper.c
    rz_rproc.c
    platform_info.c
)

if(TARGET CustomXRCEAgent)
    set(_USR_INC_HINTS)
    set(_USR_LIB_HINTS)

    list(APPEND _USR_INC_HINTS
        /usr/include
        /usr/include/openamp
        /usr/include/metal
    )

    list(APPEND _USR_LIB_HINTS
        /usr/lib/aarch64-linux-gnu
    )

    target_include_directories(CustomXRCEAgent PRIVATE ${_USR_INC_HINTS})

    set(OPENAMP_LIBRARY "" CACHE FILEPATH "Path to libopen_amp.so")
    set(METAL_LIBRARY  "" CACHE FILEPATH "Path to libmetal.so")

    if(DEFINED CMAKE_SYSROOT AND NOT CMAKE_SYSROOT STREQUAL "")
        set(OPENAMP_LIBRARY "${CMAKE_SYSROOT}/usr/lib/aarch64-linux-gnu/libopen_amp.so.0")
        set(METAL_LIBRARY  "${CMAKE_SYSROOT}/usr/lib/aarch64-linux-gnu/libmetal.so.0")
    endif()

    if(NOT OPENAMP_LIBRARY)
        find_library(OPENAMP_LIBRARY
            NAMES open_amp libopen_amp open_amp.so.0 libopen_amp.so.0
            PATHS ${_USR_LIB_HINTS} NO_DEFAULT_PATH)
    endif()

    if(NOT METAL_LIBRARY)
        find_library(METAL_LIBRARY
            NAMES metal libmetal metal.so.0 libmetal.so.0
            PATHS ${_USR_LIB_HINTS} NO_DEFAULT_PATH)
    endif()

    message(STATUS "OPENAMP_LIBRARY = ${OPENAMP_LIBRARY}")
    message(STATUS "METAL_LIBRARY   = ${METAL_LIBRARY}")

    if(NOT OPENAMP_LIBRARY OR NOT METAL_LIBRARY)
        message(FATAL_ERROR
            "OpenAMP/Metal NOT FOUND in: ${_USR_LIB_HINTS}\n")
    endif()
    if(OPENAMP_LIBRARY MATCHES "^/usr/local" OR METAL_LIBRARY MATCHES "^/usr/local")
        message(FATAL_ERROR
            "Library detected in /usr/local is NOT valid. Please install it in /usr or remove the conflicting /usr/local version.")
    endif()

    target_link_libraries(CustomXRCEAgent PRIVATE
        ${PROJECT_NAME}
        ${OPENAMP_LIBRARY}
        ${METAL_LIBRARY}
        rt
        dl
    )

    set_target_properties(CustomXRCEAgent PROPERTIES
        CXX_STANDARD 11
        CXX_STANDARD_REQUIRED YES
    )
endif()