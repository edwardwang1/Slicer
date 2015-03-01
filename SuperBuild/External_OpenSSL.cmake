
set(proj OpenSSL)

# Set dependency list
set(${proj}_DEPENDENCIES "")
if(UNIX)
  set(${proj}_DEPENDENCIES zlib)
endif()

# Include dependent projects if any
ExternalProject_Include_Dependencies(${proj} PROJECT_VAR proj DEPENDS_VAR ${proj}_DEPENDENCIES)

if(${CMAKE_PROJECT_NAME}_USE_SYSTEM_${proj})
  unset(OPENSSL_INCLUDE_DIR CACHE)
  if(UNIX)
    unset(OPENSSL_CRYPTO_LIBRARY CACHE)
    unset(OPENSSL_SSL_LIBRARY CACHE)
  elseif(WIN32)
    unset(LIB_EAY_DEBUG CACHE)
    unset(LIB_EAY_RELEASE CACHE)
    unset(SSL_EAY_DEBUG CACHE)
    unset(SSL_EAY_RELEASE CACHE)
  endif()
  find_package(OpenSSL REQUIRED)
endif()


if(UNIX)
  set(_no_openssl_libraries
    NOT DEFINED OPENSSL_CRYPTO_LIBRARY
    OR NOT DEFINED OPENSSL_SSL_LIBRARY
    )
elseif(WIN32)
  set(_no_openssl_libraries
    NOT DEFINED LIB_EAY_DEBUG
    OR NOT DEFINED LIB_EAY_RELEASE
    OR NOT DEFINED SSL_EAY_DEBUG
    OR NOT DEFINED SSL_EAY_RELEASE
    )
endif()

if((NOT DEFINED OPENSSL_LIBRARIES
   OR ${_no_openssl_libraries}) AND NOT ${CMAKE_PROJECT_NAME}_USE_SYSTEM_${proj})

  #------------------------------------------------------------------------------
  if(UNIX)
    set(OpenSSL_URL http://packages.kitware.com/download/item/7669/openssl-1.0.1l.tar.gz)
    set(OpenSSL_MD5 cdb22925fc9bc97ccbf1e007661f2aa6)

    #------------------------------------------------------------------------------
    set(EP_SOURCE_DIR ${CMAKE_BINARY_DIR}/${proj})

    include(ExternalProjectForNonCMakeProject)

    # environment
    set(_env_script ${CMAKE_BINARY_DIR}/${proj}_Env.cmake)
    ExternalProject_Write_SetBuildEnv_Commands(${_env_script})
    file(APPEND ${_env_script}
"#------------------------------------------------------------------------------
# Added by '${CMAKE_CURRENT_LIST_FILE}'
include(\"${${CMAKE_PROJECT_NAME}_CMAKE_DIR}/ExternalProjectForNonCMakeProject.cmake\")
set(CMAKE_BINARY_DIR \"${CMAKE_BINARY_DIR}\")
set(ENV{VS_UNICODE_OUTPUT} \"\")
")
    if(APPLE)
      file(APPEND ${_env_script}
"# Hint OpenSSL that we prefer a 64-bit build.
  set(ENV{KERNEL_BITS} \"64\")
  # Allow 'sysctl' executable used in OpenSSL config script to be found.
  # This is required when building Slicer using a cronjob where the
  # default environement is restricted.
  set(ENV{PATH} \"/usr/sbin:\$ENV{PATH}\")
")
    endif()

    get_filename_component(_zlib_library_dir ${ZLIB_LIBRARY} PATH)

    # configure step
    set(_configure_script ${CMAKE_BINARY_DIR}/${proj}_configure_step.cmake)
    file(WRITE ${_configure_script}
"include(\"${_env_script}\")
set(${proj}_WORKING_DIR \"${EP_SOURCE_DIR}\")
ExternalProject_Execute(${proj} \"configure-zlib\" cp ${ZLIB_LIBRARY} ${_zlib_library_dir}/libz.a
  )
ExternalProject_Execute(${proj} \"configure\" sh config --with-zlib-lib=${_zlib_library_dir} --with-zlib-include=${ZLIB_INCLUDE_DIR} threads zlib shared
  )
")

    #------------------------------------------------------------------------------
    ExternalProject_Add(${proj}
      ${${proj}_EP_ARGS}
      URL ${OpenSSL_URL}
      URL_MD5 ${OpenSSL_MD5}
      DOWNLOAD_DIR ${CMAKE_CURRENT_BINARY_DIR}
      SOURCE_DIR ${EP_SOURCE_DIR}
      BUILD_IN_SOURCE 1
      PATCH_COMMAND ${CMAKE_COMMAND} -P ${_configure_script}
      CONFIGURE_COMMAND ""
      BUILD_COMMAND make -j1 build_libs
      INSTALL_COMMAND ""
      DEPENDS
        ${${proj}_DEPENDENCIES}
      )

    if(APPLE)
      ExternalProject_Add_Step(${proj} fix_rpath
        COMMAND install_name_tool -id ${EP_SOURCE_DIR}/libcrypto.dylib ${EP_SOURCE_DIR}/libcrypto.dylib
        COMMAND install_name_tool
          -change /usr/local/ssl/lib/libcrypto.1.0.0.dylib ${EP_SOURCE_DIR}/libcrypto.dylib
          -id ${EP_SOURCE_DIR}/libssl.dylib ${EP_SOURCE_DIR}/libssl.dylib
        DEPENDEES build
        )
    endif()

    set(OpenSSL_DIR ${EP_SOURCE_DIR})
    set(OPENSSL_INCLUDE_DIR ${OpenSSL_DIR}/include)
    set(OPENSSL_LIBRARY_DIR ${OpenSSL_DIR})
    set(OPENSSL_EXPORT_LIBRARY_DIR ${OpenSSL_DIR})

    set(OPENSSL_CRYPTO_LIBRARY ${OPENSSL_LIBRARY_DIR}/libcrypto${CMAKE_SHARED_LIBRARY_SUFFIX})
    set(OPENSSL_SSL_LIBRARY ${OPENSSL_LIBRARY_DIR}/libssl${CMAKE_SHARED_LIBRARY_SUFFIX})

    set(OPENSSL_LIBRARIES ${OPENSSL_CRYPTO_LIBRARY} ${OPENSSL_SSL_LIBRARY})

    ExternalProject_Message(${proj} "OPENSSL_CRYPTO_LIBRARY:${OPENSSL_CRYPTO_LIBRARY}")
    ExternalProject_Message(${proj} "OPENSSL_SSL_LIBRARY:${OPENSSL_SSL_LIBRARY}")

  #------------------------------------------------------------------------------
  elseif(WIN32)
    set(_qt_version "${QT_VERSION_MAJOR}.${QT_VERSION_MINOR}.${QT_VERSION_PATCH}")

    # Starting with Qt 4.8.6, we compiled [1] OpenSSL binaries specifically for each
    # version of Microsoft Visual Studio. To understand the motivation, read below.
    #
    # As explained in [2][3], if a library meets these two conditions:
    #   (a) exposes a pure C interface
    #   (b) is linked against static version of the CRT
    # the version of the compiler and runtime used to build the library
    # shouldn't matter.
    #
    # That said, since OpenSSL is built as a shared library using the '/MD' [4]
    # flag, it is not possible to use the same library with different runtime
    # libraries.
    #
    # We found out that '/MD' was used by inspecting the the file 'ms/ntdll.mak'
    # generated atfer configuring OpenSSL.
    #
    # If you find mistake in this explanation, do not hesitate to submit a patch
    # to fix this text. Thanks.
    #
    # [1] Script used to compile OpenSSL: https://gist.github.com/jcfr/6030240
    # [2] http://siomsystems.com/mixing-visual-studio-versions/
    # [3] http://bytes.com/topic/net/answers/505515-compile-different-versions-visual-studio
    # [4] http://msdn.microsoft.com/en-us/library/2kzt1wy3.aspx

    set(_error_msg "There is no pre-compiled version of OpenSSL available for
this version of visual studio [${MSVC_VERSION}]. You could either:
 (1) disable SSL support configuring with option Slicer_USE_PYTHONQT_WITH_OPENSSL:BOOL=OFF
 or
 (2) configure Slicer providing your own version of OpenSSL that matches the version
     of OpenSSL also used to compile Qt library.
     The option to specify are OPENSSL_INCLUDE_DIR, LIB_EAY_DEBUG, LIB_EAY_RELEASE,
     SSL_EAY_DEBUG and SSL_EAY_RELEASE.")

    #--------------------
    if(CMAKE_SIZEOF_VOID_P EQUAL 4) # 32-bit

      # OpenSSL 1.0.1l
      if(MSVC_VERSION VERSION_EQUAL "1500")
        set(OpenSSL_URL http://packages.kitware.com/download/item/7806/OpenSSL_1_0_1l-install-msvc1500-32.tar.gz)
        set(OpenSSL_MD5 85218e0ea7bd15457f66cc04170560d5)
      elseif(MSVC_VERSION VERSION_EQUAL "1600")
        set(OpenSSL_URL http://packages.kitware.com/download/item/7809/OpenSSL_1_0_1l-install-msvc1600-32.tar.gz)
        set(OpenSSL_MD5 3f756fc731fb95f919ea24f2ec979732)
      else()
        message(FATAL_ERROR ${_error_msg})
      endif()

    #--------------------
    elseif(CMAKE_SIZEOF_VOID_P EQUAL 8) # 64-bit

      # OpenSSL 1.0.1l
      if(MSVC_VERSION VERSION_EQUAL "1500")
        set(OpenSSL_URL http://packages.kitware.com/download/item/7803/OpenSSL_1_0_1l-install-msvc1500-64.tar.gz)
        set(OpenSSL_MD5 ce819931504f8e7c5d9024215b2cc9cf)
      else(MSVC_VERSION VERSION_EQUAL "1600")
        set(OpenSSL_URL http://packages.kitware.com/download/item/7700/OpenSSL_1_0_1l-install-msvc1600-64.tar.gz)
        set(OpenSSL_MD5 07d259e1a467d9c7a7d9cddfd77e8915)
      else()
        message(FATAL_ERROR ${_error_msg})
      endif()

    endif()

    #------------------------------------------------------------------------------
    set(EP_SOURCE_DIR ${CMAKE_BINARY_DIR}/${proj}-install)

    ExternalProject_Add(${proj}
      ${${proj}_EP_ARGS}
      URL ${OpenSSL_URL}
      URL_MD5 ${OpenSSL_MD5}
      DOWNLOAD_DIR ${CMAKE_CURRENT_BINARY_DIR}
      SOURCE_DIR ${EP_SOURCE_DIR}
      CONFIGURE_COMMAND ""
      BUILD_COMMAND ""
      INSTALL_COMMAND ""
      DEPENDS
        ${${proj}_DEPENDENCIES}
      )

    set(OpenSSL_DIR ${EP_SOURCE_DIR})
    if(DEFINED CMAKE_CONFIGURATION_TYPES)
      set(OpenSSL_DIR ${OpenSSL_DIR}/${CMAKE_CFG_INTDIR})
    else()
      set(OpenSSL_DIR ${OpenSSL_DIR}/${CMAKE_BUILD_TYPE})
    endif()

    set(OPENSSL_INCLUDE_DIR "${OpenSSL_DIR}/include")
    set(OPENSSL_LIBRARY_DIR "${OpenSSL_DIR}/lib")
    set(OPENSSL_EXPORT_LIBRARY_DIR "${OpenSSL_DIR}/bin")
    set(OPENSSL_LIBRARIES "${OPENSSL_LIBRARY_DIR}/libeay32.lib" "${OPENSSL_LIBRARY_DIR}/ssleay32.lib")

    set(LIB_EAY_DEBUG "${EP_SOURCE_DIR}/Debug/lib/libeay32.lib")
    set(LIB_EAY_RELEASE "${EP_SOURCE_DIR}/Release/lib/libeay32.lib")
    set(SSL_EAY_DEBUG "${EP_SOURCE_DIR}/Debug/lib/ssleay32.lib")
    set(SSL_EAY_RELEASE "${EP_SOURCE_DIR}/Release/lib/ssleay32.lib")

    ExternalProject_Message(${proj} "LIB_EAY_DEBUG:${LIB_EAY_DEBUG}")
    ExternalProject_Message(${proj} "LIB_EAY_RELEASE:${LIB_EAY_RELEASE}")
    ExternalProject_Message(${proj} "SSL_EAY_DEBUG:${SSL_EAY_DEBUG}")
    ExternalProject_Message(${proj} "SSL_EAY_RELEASE:${SSL_EAY_RELEASE}")
  endif()

  #-----------------------------------------------------------------------------
  # Launcher setting specific to build tree

  set(${proj}_LIBRARY_PATHS_LAUNCHER_BUILD ${OPENSSL_EXPORT_LIBRARY_DIR})
  mark_as_superbuild(
    VARS ${proj}_LIBRARY_PATHS_LAUNCHER_BUILD
    LABELS "LIBRARY_PATHS_LAUNCHER_BUILD"
    )

  ExternalProject_Message(${proj} "OPENSSL_LIBRARY_DIR:${OPENSSL_LIBRARY_DIR}")
  ExternalProject_Message(${proj} "OPENSSL_EXPORT_LIBRARY_DIR:${OPENSSL_EXPORT_LIBRARY_DIR}")
else()
  ExternalProject_Add_Empty(${proj} DEPENDS ${${proj}_DEPENDENCIES})
endif()

mark_as_superbuild(
  VARS OPENSSL_INCLUDE_DIR:PATH
  LABELS "FIND_PACKAGE"
  )

mark_as_superbuild(
  VARS
    OPENSSL_LIBRARIES:STRING
    OPENSSL_EXPORT_LIBRARY_DIR:PATH
  )

if(UNIX)
  mark_as_superbuild(
    VARS
      OPENSSL_SSL_LIBRARY:FILEPATH
      OPENSSL_CRYPTO_LIBRARY:FILEPATH
    LABELS "FIND_PACKAGE"
    )
elseif(WIN32)
  mark_as_superbuild(
    VARS
      LIB_EAY_DEBUG:FILEPATH
      LIB_EAY_RELEASE:FILEPATH
      SSL_EAY_DEBUG:FILEPATH
      SSL_EAY_RELEASE:FILEPATH
    LABELS "FIND_PACKAGE"
    )
endif()

ExternalProject_Message(${proj} "OPENSSL_INCLUDE_DIR:${OPENSSL_INCLUDE_DIR}")
ExternalProject_Message(${proj} "OPENSSL_LIBRARIES:${OPENSSL_LIBRARIES}")
