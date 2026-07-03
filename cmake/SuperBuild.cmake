# Copyright 2019 Proyectos y Sistemas de Mantenimiento SL (eProsima).
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

include(ExternalProject)

unset(_deps)

enable_language(C)
enable_language(CXX)

if(ANDROID)
    set(CROSS_CMAKE_ARGS
        -DCMAKE_SYSTEM_VERSION:STRING=${CMAKE_SYSTEM_VERSION}
        -DCMAKE_ANDROID_ARCH_ABI:STRING=${CMAKE_ANDROID_ARCH_ABI}
        )
endif()

# Pass Poky environment setup path to ExternalProject subprocesses so cross.cmake can source it.
# Cache variable (explicit -D) is checked FIRST and takes precedence over an inherited environment
# variable: compile.sh always exports POKY_ENVIRONMENT_SETUP, so an env-first check meant the
# ${POKY_ENVIRONMENT_SETUP} cache dereference below was never reached whenever both were set --
# CMake then reports the -D value as an unused "manually-specified variable" even though it always
# agreed with the env var in practice.
if(DEFINED POKY_ENVIRONMENT_SETUP)
    list(APPEND CROSS_CMAKE_ARGS -DPOKY_ENVIRONMENT_SETUP:STRING=${POKY_ENVIRONMENT_SETUP})
elseif(DEFINED ENV{POKY_ENVIRONMENT_SETUP})
    list(APPEND CROSS_CMAKE_ARGS -DPOKY_ENVIRONMENT_SETUP:STRING=$ENV{POKY_ENVIRONMENT_SETUP})
endif()

if(UAGENT_P2P_PROFILE)
    # Micro XRCE-DDS Client.
    unset(microxrcedds_client_DIR CACHE)
    find_package(microxrcedds_client ${_microxrcedds_client_version} EXACT QUIET)
    if(NOT microxrcedds_client_FOUND)
        ExternalProject_Add(microxrcedds_client
            GIT_REPOSITORY
                https://github.com/eProsima/Micro-XRCE-DDS-Client.git
            GIT_TAG
                ${_microxrcedds_client_tag}
            PREFIX
                ${PROJECT_BINARY_DIR}/microxrcedds_client
            INSTALL_DIR
                ${PROJECT_BINARY_DIR}/temp_install
            CMAKE_CACHE_ARGS
                -DCMAKE_INSTALL_PREFIX:PATH=<INSTALL_DIR>
                -DCMAKE_PREFIX_PATH:PATH=${CMAKE_PREFIX_PATH}
                -DCMAKE_FIND_ROOT_PATH:PATH=${PROJECT_BINARY_DIR}/temp_install
                -DCMAKE_CXX_COMPILER:FILEPATH=${CMAKE_CXX_COMPILER}
                -DCMAKE_C_COMPILER:FILEPATH=${CMAKE_C_COMPILER}
                -DBUILD_SHARED_LIBS:BOOL=${BUILD_SHARED_LIBS}
                -DCMAKE_BUILD_TYPE:STRING=${CMAKE_BUILD_TYPE}
                -DCMAKE_TOOLCHAIN_FILE:PATH=${CMAKE_TOOLCHAIN_FILE}
                ${CROSS_CMAKE_ARGS}
                -DUCLIENT_ISOLATED_INSTALL:BOOL=ON
            )
        list(APPEND _deps microxrcedds_client)
    endif()
endif()

# Fast CDR.
if(NOT UAGENT_USE_SYSTEM_FASTCDR)
    unset(fastcdr_DIR CACHE)
    find_package(fastcdr ${_fastcdr_version} EXACT QUIET)
    if(NOT fastcdr_FOUND)
        ExternalProject_Add(fastcdr
            GIT_REPOSITORY
                https://github.com/eProsima/Fast-CDR.git
            GIT_TAG
                ${_fastcdr_tag}
            PREFIX
                ${PROJECT_BINARY_DIR}/fastcdr
            INSTALL_DIR
                ${PROJECT_BINARY_DIR}/temp_install/fastcdr-${_fastcdr_version}
            CMAKE_CACHE_ARGS
                -DCMAKE_INSTALL_PREFIX:PATH=<INSTALL_DIR>
                -DCMAKE_PREFIX_PATH:PATH=${CMAKE_PREFIX_PATH}
                -DCMAKE_CXX_COMPILER:FILEPATH=${CMAKE_CXX_COMPILER}
                -DCMAKE_C_COMPILER:FILEPATH=${CMAKE_C_COMPILER}
                -DBUILD_SHARED_LIBS:BOOL=${BUILD_SHARED_LIBS}
                -DCMAKE_BUILD_TYPE:STRING=${CMAKE_BUILD_TYPE}
                -DCMAKE_TOOLCHAIN_FILE:PATH=${CMAKE_TOOLCHAIN_FILE}
                ${CROSS_CMAKE_ARGS}
            PATCH_COMMAND
                ${CMAKE_COMMAND} -E chdir <SOURCE_DIR> patch -p1 -N --silent < ${PROJECT_SOURCE_DIR}/patches/fastcdr_alignment.patch || true
            UPDATE_COMMAND
                COMMAND ${CMAKE_COMMAND} -E copy <SOURCE_DIR>/src/cpp/CMakeLists.txt <SOURCE_DIR>/src/cpp/CMakeLists.txt.bak
                COMMAND ${CMAKE_COMMAND} -DSOVERSION_FILE=<SOURCE_DIR>/src/cpp/CMakeLists.txt -P ${PROJECT_SOURCE_DIR}/cmake/Soversion.cmake
            TEST_COMMAND
                COMMAND ${CMAKE_COMMAND} -E rename <SOURCE_DIR>/src/cpp/CMakeLists.txt.bak <SOURCE_DIR>/src/cpp/CMakeLists.txt
            )
        list(APPEND _deps fastcdr)
    endif()
endif()

if(UAGENT_FAST_PROFILE AND NOT UAGENT_USE_SYSTEM_FASTDDS)
    # Foonathan memory.
    unset(foonathan_memory_DIR CACHE)
    set(_foonathan_memory_cmake_dir "")
    find_package(foonathan_memory QUIET)
    if (NOT foonathan_memory_FOUND)
        ExternalProject_Add(foonathan_memory
            GIT_REPOSITORY
                https://github.com/foonathan/memory.git
            GIT_TAG
                ${_foonathan_memory_tag}
            PREFIX
                ${PROJECT_BINARY_DIR}/foonathan_memory
            INSTALL_DIR
                ${PROJECT_BINARY_DIR}/temp_install/foonathan_memory
            CMAKE_CACHE_ARGS
                -DCMAKE_INSTALL_PREFIX:PATH=<INSTALL_DIR>
                -DFOONATHAN_MEMORY_BUILD_EXAMPLES:BOOL=OFF
                -DFOONATHAN_MEMORY_BUILD_TESTS:BOOL=OFF
                -DFOONATHAN_MEMORY_BUILD_TOOLS:BOOL=ON
                -DCMAKE_POSITION_INDEPENDENT_CODE:BOOL=ON
                -DCMAKE_BUILD_TYPE:STRING=${CMAKE_BUILD_TYPE}
                -DCMAKE_TOOLCHAIN_FILE:PATH=${CMAKE_TOOLCHAIN_FILE}
                ${CROSS_CMAKE_ARGS}
            )
        set(_foonathan_memory_cmake_dir "${PROJECT_BINARY_DIR}/temp_install/foonathan_memory/lib/foonathan_memory/cmake")
    endif()

    # Fast DDS.
    unset(fastdds_DIR CACHE)
    find_package(fastdds ${_fastdds_version} EXACT QUIET)
    if(NOT fastdds_FOUND)
        set(_fastdds_cache_args
                -DCMAKE_INSTALL_PREFIX:PATH=<INSTALL_DIR>
                -DCMAKE_PREFIX_PATH:PATH=${CMAKE_PREFIX_PATH};${PROJECT_BINARY_DIR}/temp_install
                # Point Fast-DDS at the SuperBuild's OWN FastCDR (same as the uagent target below)
                # so it reuses the shared FastCDR instead of building its bundled thirdparty/fastcdr.
                # Without this, Fast-DDS only resolves FastCDR via find_package over the prefix, which
                # is fragile under a cross toolchain's CMAKE_FIND_ROOT_PATH_MODE_PACKAGE=ONLY +
                # per-dependency prefix entries: once temp_install is populated the lookup misses and
                # Fast-DDS falls back to its bundled FastCDR (a DIFFERENT version) — splitting the
                # FastCDR ABI between libfastdds and the agent. (foonathan_memory_DIR is passed below
                # for the same reason; fastcdr_DIR was simply omitted here.)
                -Dfastcdr_DIR:PATH=${PROJECT_BINARY_DIR}/temp_install/fastcdr-${_fastcdr_version}/lib/cmake/fastcdr
                -DBUILD_SHARED_LIBS:BOOL=${BUILD_SHARED_LIBS}
                -DCMAKE_TOOLCHAIN_FILE:PATH=${CMAKE_TOOLCHAIN_FILE}
                ${CROSS_CMAKE_ARGS}
                -DCMAKE_FIND_ROOT_PATH:PATH=${PROJECT_BINARY_DIR}/temp_install
                -DCMAKE_BUILD_TYPE:STRING=${CMAKE_BUILD_TYPE}
                -DCMAKE_CXX_COMPILER:FILEPATH=${CMAKE_CXX_COMPILER}
                -DCMAKE_C_COMPILER:FILEPATH=${CMAKE_C_COMPILER}
                -DCMAKE_SHARED_LINKER_FLAGS:STRING=-Wl,-Bsymbolic
                -DTHIRDPARTY:BOOL=ON
                -DTINYXML2_FROM_SOURCE:BOOL=ON
                -DTINYXML2_INCLUDE_DIR:PATH=<SOURCE_DIR>/thirdparty/tinyxml2
                -DTINYXML2_SOURCE_DIR:PATH=<SOURCE_DIR>/thirdparty/tinyxml2
                -DCOMPILE_TOOLS:BOOL=OFF
                -DSECURITY:BOOL=${UAGENT_SECURITY_PROFILE}
                -DSHM_TRANSPORT_DEFAULT:BOOL=OFF
        )
        if(_foonathan_memory_cmake_dir)
            list(APPEND _fastdds_cache_args "-Dfoonathan_memory_DIR:PATH=${_foonathan_memory_cmake_dir}")
        endif()
        ExternalProject_Add(fastdds
            GIT_REPOSITORY
                https://github.com/eProsima/Fast-DDS.git
            GIT_TAG
                ${_fastdds_tag}
            PREFIX
                ${PROJECT_BINARY_DIR}/fastdds
            INSTALL_DIR
                ${PROJECT_BINARY_DIR}/temp_install/fastdds-${_fastdds_version}
            CMAKE_CACHE_ARGS
                ${_fastdds_cache_args}
            PATCH_COMMAND
                ${CMAKE_COMMAND} -E chdir <SOURCE_DIR> patch -p1 -N --silent < ${PROJECT_SOURCE_DIR}/patches/fastdds_fastcdr_alignment.patch || true
            DEPENDS
                fastcdr
                foonathan_memory
            UPDATE_COMMAND
                COMMAND ${CMAKE_COMMAND} -E copy <SOURCE_DIR>/src/cpp/CMakeLists.txt <SOURCE_DIR>/src/cpp/CMakeLists.txt.bak
                COMMAND ${CMAKE_COMMAND} -DSOVERSION_FILE=<SOURCE_DIR>/src/cpp/CMakeLists.txt -P ${PROJECT_SOURCE_DIR}/cmake/Soversion.cmake
            TEST_COMMAND
                COMMAND ${CMAKE_COMMAND} -E rename <SOURCE_DIR>/src/cpp/CMakeLists.txt.bak <SOURCE_DIR>/src/cpp/CMakeLists.txt
            )
        list(APPEND _deps fastdds)
    endif()
endif()

if(UAGENT_LOGGER_PROFILE AND NOT UAGENT_USE_SYSTEM_LOGGER)
    # spdlog.
    unset(spdlog_DIR CACHE)
    find_package(spdlog ${_spdlog_version} EXACT QUIET)
    if(NOT spdlog_FOUND)
        ExternalProject_Add(spdlog
            GIT_REPOSITORY
                https://github.com/gabime/spdlog.git
            GIT_TAG
                ${_spdlog_tag}
            PREFIX
                ${PROJECT_BINARY_DIR}/spdlog
            INSTALL_DIR
                ${PROJECT_BINARY_DIR}/temp_install/spdlog-${_spdlog_version}
            CMAKE_CACHE_ARGS
                -DCMAKE_INSTALL_PREFIX:PATH=<INSTALL_DIR>
                -DCMAKE_PREFIX_PATH:PATH=${CMAKE_PREFIX_PATH};${CMAKE_INSTALL_PREFIX}
                -DBUILD_SHARED_LIBS:BOOL=OFF
                -DCMAKE_TOOLCHAIN_FILE:PATH=${CMAKE_TOOLCHAIN_FILE}
                ${CROSS_CMAKE_ARGS}
                -DCMAKE_BUILD_TYPE:STRING=${CMAKE_BUILD_TYPE}
                -DCMAKE_CXX_COMPILER:FILEPATH=${CMAKE_CXX_COMPILER}
                -DCMAKE_C_COMPILER:FILEPATH=${CMAKE_C_COMPILER}
                -DCMAKE_POSITION_INDEPENDENT_CODE:BOOL=ON
                -DSPDLOG_BUILD_EXAMPLES:BOOL=OFF
                -DSPDLOG_BUILD_BENCH:BOOL=OFF
                -DSPDLOG_BUILD_TESTS:BOOL=OFF
                -DSPDLOG_INSTALL:BOOL=ON
            )
        list(APPEND _deps spdlog)
    endif()
endif()

# googletest.
if(UAGENT_BUILD_TESTS)
    unset(googletest_DIR CACHE)
    enable_language(CXX)
    find_package(GTest QUIET)
    find_package(GMock QUIET)
    if(NOT GTest_FOUND OR NOT GMock_FOUND OR UAGENT_USE_INTERNAL_GTEST)
        unset(GTEST_ROOT CACHE)
        unset(GMOCK_ROOT CACHE)
        ExternalProject_Add(googletest
            GIT_REPOSITORY
                https://github.com/google/googletest.git
            GIT_TAG
                release-1.11.0
            PREFIX
                ${PROJECT_BINARY_DIR}/googletest
            INSTALL_DIR
                ${PROJECT_BINARY_DIR}/temp_install/googletest
            CMAKE_ARGS
                -DCMAKE_INSTALL_PREFIX:PATH=<INSTALL_DIR>
                -DCMAKE_TOOLCHAIN_FILE:PATH=${CMAKE_TOOLCHAIN_FILE}
                $<$<PLATFORM_ID:Windows>:-Dgtest_force_shared_crt:BOOL=ON>
            BUILD_COMMAND
                COMMAND ${CMAKE_COMMAND} --build <BINARY_DIR> --config Release --target install
                COMMAND ${CMAKE_COMMAND} --build <BINARY_DIR> --config Debug --target install
            INSTALL_COMMAND
                ""
            )
        set(GTEST_ROOT ${PROJECT_BINARY_DIR}/temp_install/googletest CACHE INTERNAL "")
        set(GMOCK_ROOT ${PROJECT_BINARY_DIR}/temp_install/googletest CACHE INTERNAL "")
        set(UAGENT_USE_INTERNAL_GTEST ON)
        list(APPEND _deps googletest)
    endif()
endif()

# Main project.
ExternalProject_Add(uagent
    SOURCE_DIR
        ${PROJECT_SOURCE_DIR}
    BINARY_DIR
        ${CMAKE_CURRENT_BINARY_DIR}
    CMAKE_CACHE_ARGS
        -DUAGENT_SUPERBUILD:BOOL=OFF
        -DUAGENT_USE_INTERNAL_GTEST:BOOL=${UAGENT_USE_INTERNAL_GTEST}
        -DCMAKE_PREFIX_PATH:PATH=${PROJECT_BINARY_DIR}/temp_install
        -DCMAKE_FIND_ROOT_PATH:PATH=${PROJECT_BINARY_DIR}/temp_install;${CMAKE_FIND_ROOT_PATH}
        -Dfastcdr_DIR:PATH=${PROJECT_BINARY_DIR}/temp_install/fastcdr-${_fastcdr_version}/lib/cmake/fastcdr
        -Dfastdds_DIR:PATH=${PROJECT_BINARY_DIR}/temp_install/fastdds-${_fastdds_version}/share/fastdds/cmake
        -Dfoonathan_memory_DIR:PATH=${PROJECT_BINARY_DIR}/temp_install/foonathan_memory/lib/foonathan_memory/cmake
        -Dspdlog_DIR:PATH=${PROJECT_BINARY_DIR}/temp_install/spdlog-${_spdlog_version}/lib/cmake/spdlog
        -DCMAKE_TOOLCHAIN_FILE:PATH=${CMAKE_TOOLCHAIN_FILE}
        -DCMAKE_CXX_COMPILER:FILEPATH=${CMAKE_CXX_COMPILER}
        -DCMAKE_C_COMPILER:FILEPATH=${CMAKE_C_COMPILER}
        ${CROSS_CMAKE_ARGS}
    INSTALL_COMMAND
        ""
    DEPENDS
        ${_deps}
    )
