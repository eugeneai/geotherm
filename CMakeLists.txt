cmake_minimum_required(VERSION 3.26)

project(Geotherm VERSION 0.1 LANGUAGES CXX)

set(CMAKE_AUTOUIC ON)
set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_VERBOSE_MAKEFILE TRUE)

find_package(QT NAMES Qt6 REQUIRED COMPONENTS Core Widgets LinguistTools)
find_package(Qt6 REQUIRED COMPONENTS Widgets LinguistTools WebEngineWidgets)
qt_standard_project_setup()

# set(CMAKE_MODULE_PATH ${CMAKE_CURRENT_SOURCE_DIR})


exec_program(julia
  ARGS "-e 'print(joinpath(Sys.BINDIR, Base.DATAROOTDIR, \"julia\"))'"
  OUTPUT_VARIABLE JULIA_SHARE
)

set(JULIA_CFG ${JULIA_SHARE}/julia-config.jl)

message(STATUS "JULIA_CFG: " ${JULIA_CFG})

exec_program(julia
  ARGS ${JULIA_CFG} --cflags
  OUTPUT_VARIABLE JULIA_CFLAGS
)

set(JULIA_CXXFLAGS ${JULIA_CFLAGS})

exec_program(julia
  ARGS ${JULIA_CFG} --ldflags
  OUTPUT_VARIABLE JULIA_LDFLAGS
)

exec_program(julia
  ARGS ${JULIA_CFG} --ldlibs
  OUTPUT_VARIABLE JULIA_LDLIBS
)

set(TS_FILES Geotherm_ru_RU.ts)

set(PROJECT_SOURCES
        main.cpp
        embedding.cpp
        embedding.h
        geothermmainwindow.cpp
        geothermmainwindow.h
        geothermmainwindow.ui
        aboutdialog.cpp
        aboutdialog.h
        aboutdialog.ui
        ${TS_FILES}
)


if(${QT_VERSION_MAJOR} GREATER_EQUAL 6)
    qt_add_executable(Geotherm
        MANUAL_FINALIZATION
        ${PROJECT_SOURCES}
    )
# Define target properties for Android with Qt 6 as:
#    set_property(TARGET Geotherm APPEND PROPERTY QT_ANDROID_PACKAGE_SOURCE_DIR
#                 ${CMAKE_CURRENT_SOURCE_DIR}/android)
# For more information, see https://doc.qt.io/qt-6/qt-add-executable.html#target-creation

    qt_create_translation(QM_FILES ${CMAKE_SOURCE_DIR} ${TS_FILES})
else()
    if(ANDROID)
        add_library(Geotherm SHARED
            ${PROJECT_SOURCES}
        )
# Define properties for Android with Qt 5 after find_package() calls as:
#    set(ANDROID_PACKAGE_SOURCE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/android")
    else()
        add_executable(Geotherm
            ${PROJECT_SOURCES}
        )
    endif()

    qt5_create_translation(QM_FILES ${CMAKE_SOURCE_DIR} ${TS_FILES})
endif()

target_link_libraries(Geotherm
  PRIVATE
  Qt6::Widgets
  Qt6::Core
  Qt6::WebEngineWidgets
  ${JULIA_LDFLAGS} ${JULIA_LDLIBS}
)

# target_compile_options(Geotherm PRIVATE ${JULIA_CXXFLAGS})
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} ${JULIA_CXXFLAGS} -O0 -ggdb")


set_target_properties(Geotherm PROPERTIES
    MACOSX_BUNDLE_GUI_IDENTIFIER my.example.com
    MACOSX_BUNDLE_BUNDLE_VERSION ${PROJECT_VERSION}
    MACOSX_BUNDLE_SHORT_VERSION_STRING ${PROJECT_VERSION_MAJOR}.${PROJECT_VERSION_MINOR}
    MACOSX_BUNDLE TRUE
    WIN32_EXECUTABLE TRUE
)

install(TARGETS Geotherm
    BUNDLE DESTINATION .
    LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR})

if(QT_VERSION_MAJOR EQUAL 6)
    qt_finalize_executable(Geotherm)
endif()
