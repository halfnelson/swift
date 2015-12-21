Param(
    [string]${build-args}  = "",
    [string]${build-dir} = "",
    [string]${cmark-build-type} = "Debug",
    [string]${lldb-extra-cmake-args} = "",
    [Bool]${lldb-no-debugserver} = $true,
    [string]${llvm-build-type} = "Debug",
    [Bool]${llvm-enable-assertions} = $true,
    [string]${swift-build-type} = "Debug",
    [Bool]${swift-enable-assertions} = $true,
    [string]${swift-stdlib-build-type} = "Debug",
    [Bool]${swift-stdlib-enable-assertions} = $true,
    [string]${lldb-build-type} = "Debug",
    [string]${llbuild-build-type} = "Debug",
    [string]${foundation-build-type} = "Debug",
    [Bool]${llbuild-enable-assertions} = $true,
    [Switch]${enable-asan},
    [string]${cmake},
    [string]${user-config-args},
    [string]${cmake-generator} = "Ninja",
    [Switch]${verbose-build},
    [string]${install-prefix},
    [string]${install-destdir},
    [string]${install-symroot},
    [switch]${reconfigure},

    [switch]${skip-build},
    [switch]${skip-build-cmark},
    [switch]${skip-build-llvm},
    [switch]${skip-build-swift},
    [switch]${skip-build-lldb},
    [switch]${skip-build-llbuild},
    [switch]${skip-build-swiftpm},
    [switch]${skip-build-foundation},
    [switch]${skip-test-cmark},
    [switch]${skip-test-lldb},
    [switch]${skip-test-swift},
    [switch]${skip-test-llbuild},
    [switch]${skip-test-swiftpm},
    [switch]${skip-test-foundation},
    [switch]${skip-test-validation},
    [switch]${skip-test-optimized},
    [string]${workspace},
    [bool]${enable-llvm-assertions} = $true,
    [bool]${build-llvm} = $true,
    [bool]${build-swift-tools} = $true,
    [bool]${build-swift-stdlib} = $true,
    [bool]${build-swift-sdk-overlay} = $true,
    [bool]${build-swift-static-stdlib},
    [bool]${build-swift-examples} = $true,
    [bool]${build-swift-perf-testsuite},
    [bool]${source-tree-includes-tests},
    [string]${native-llvm-tools-path}, 
    [string]${native-clang-tools-path},
    [string]${native-swift-tools-path},
    [string]${compiler-vendor} = "none",
    [string]${swift-compiler-version}, 
    [string]${clang-compiler-version},
    [bool]${embed-bitcode-section} = $false,

    [switch]${install-cmark},
    [switch]${install-swift},
    [switch]${install-lldb},
    [switch]${install-llbuild},
    [switch]${install-swiftpm},
    [switch]${install-xctest},   
    [switch]${install-foundation},

    [string]${extra-swift-args},
    [bool]${sil-verify-all} = $false,
    [bool]${swift-enable-ast-verifier} = $true,
    [bool]${swift-runtime-enable-dtrace} = $false,
    [bool]${swift-runtime-enable-leak-checker} = $false,
    [switch]${use-gold-linker},
    [string]${build-jobs}
)

if (!$workspace) {
    $workspace = Resolve-Path ((split-path -parent $MyInvocation.MyCommand.Definition).ToString() + "\..\..\")
}

#
# Options that can be "configured" by editing this file.
#
# These options are not exposed as command line options on purpose.  If you
# need to change any of these, you should do so on trunk or in a branch.
#

$LLVM_TARGETS_TO_BUILD = "X86;ARM;AArch64"

#
# End of configurable options.
#


function toupper {
    param( [string]$str )
    $str.ToUpperInvariant()
}

function true_false {
    param( $thing )
    if ($thing) {
        "TRUE"
    } else {
        "FALSE"
    }
}

function get_make_parallelism {
   (Get-WmiObject �class Win32_processor | select NumberOfCores).NumberOfCores
}

function set_lldb_build_mode() {
    ${script:lldb-build-mode} = "CustomSwift-${lldb-build-type}"
}

[System.Collections.ArrayList]$llvm_cmake_options=@()
[System.Collections.ArrayList]$swift_cmake_options=@()
[System.Collections.ArrayList]$cmark_cmake_options=@()
[System.Collections.ArrayList]$swiftpm_bootstrap_options=@()

function set_deployment_target_based_options() {
    param( [string]${deployment-target} )
    [System.Collections.ArrayList]$script:llvm_cmake_options=@()
   [System.Collections.ArrayList]$script:swift_cmake_options=@()
    [System.Collections.ArrayList]$script:cmark_cmake_options=@()
    [System.Collections.ArrayList]$script:swiftpm_bootstrap_options=@()
    ${script:swift-host-variant-arch}="x86_64"
}


if (${skip-build}) {
    ${SKIP-BUILD-CMARK} = $true
    ${SKIP-BUILD-LLVM} = $true
    ${SKIP-BUILD-SWIFT} = $true
    ${SKIP-BUILD-LLDB} = $true
    ${SKIP-BUILD-LLBUILD} = $true
    ${SKIP-BUILD-SWIFTPM} = $true
    ${SKIP-BUILD-FOUNDATION} = $true
}

# WORKSPACE, BUILD_DIR must be absolute paths

if (${workspace}) {
    ${workspace} = Resolve-Path ${workspace}
} else {
    Write-Host "workspace is required"
    Exit
}

if (${build-dir}) {
    ${build-dir} =  ${build-dir}
} else {
    Write-Host "build-dir is required"
    Exit
}

if (!(Test-Path ${workspace})) {
    Write-Host "workspace must exist"
    Exit
}

#
# Set default values for command-line parameters.
#
if (!${cmake}) {
   ${cmake} = $(cmd /C where cmake)
   if (!${cmake}) {
      ${cmake} = "c:\\Program Files (x86)\\CMake\\bin\\cmake.exe"
   }
}

if (!${install-prefix}) {
    ${install-prefix} = "bin"
}

[System.Collections.ArrayList]${native-tools-deployment-targets} = @("windows-x86_64")
[System.Collections.ArrayList]${cross-tools-deployment-targets} = @()

function is_native_tools_deployment_target {
   param([string]$deployment_target)
   ${native-tools-deployment-targets}.Contains($deployment_target)
}

function is_cross_tools_deployment_target {
   param([string]$deployment_target)
   ${cross-tools-deployment-targets}.Contains($deployment_target)
}
[System.Collections.ArrayList]${stdlib-deployment-targets} = @("windows-x86_64")


$SWIFT_SOURCE_DIR="$workspace/swift"
$LLVM_SOURCE_DIR="$workspace/llvm"
$CMARK_SOURCE_DIR="$workspace/cmark"
$LLDB_SOURCE_DIR="$workspace/lldb"
$LLBUILD_SOURCE_DIR="$workspace/llbuild"
$SWIFTPM_SOURCE_DIR="$workspace/swiftpm"
$FOUNDATION_SOURCE_DIR="$workspace/swift-corelibs-foundation"

if (!(${skip-build-cmark}) -and !(Test-Path $CMARK_SOURCE_DIR)) {
    Write-Host "Couldn't find cmark source dir"
    Exit
}


if (!(${skip-build-llbuild}) -and !(Test-Path $LLBUILD_SOURCE_DIR)) {
    Write-Host "Couldn't find llbuild source dir"
    Exit
}

if (!(${skip-build-swiftpm}) -and !(Test-Path $SWIFTPM_SOURCE_DIR)) {
    Write-Host "Couldn't find swiftpm source dir"
    Exit
}


if (!(${skip-build-foundation}) -and !(Test-Path $FOUNDATION_SOURCE_DIR)) {
    Write-Host "Couldn't find Foundation source dir"
    Exit
}

# Symlink clang into the llvm tree.
$CLANG_SOURCE_DIR="$LLVM_SOURCE_DIR/tools/clang"

if (!(Test-Path "$workspace/clang")) {
     # If llvm/tools/clang is already a directory, use that and skip the symlink.
    if (!Test-Path $CLANG_SOURCE_DIR) {
        Write-Host "Can't find source directory for clang (tried ${WORKSPACE}/clang and ${CLANG_SOURCE_DIR})"
        Exit
    }
}

if (!(Test-Path $CLANG_SOURCE_DIR)) {
    $(cmd /C mklink /d "$CLANG_SOURCE_DIR" "$workspace/clang")
}

[System.Collections.ArrayList]$PRODUCTS=@("cmark","llvm","swift")

if (!${skip-build-lldb}) {
    $PRODUCTS.Add("lldb")
}

if (!${skip-build-llbuild}) {
    $PRODUCTS.Add("llbuild")
}

if (!${skip-build-swiftpm}) {
    $PRODUCTS.Add("swiftpm")
}

if (!${skip-build-foundation}) {
    $PRODUCTS.Add("foundation")
}


[System.Collections.ArrayList]$SWIFT_STDLIB_TARGETS=@("swift-stdlib-windows-x86_64")
[System.Collections.ArrayList]$SWIFT_TEST_TARGETS=@()
if (${skip-test-validation}) {
    $SWIFT_TEST_TARGETS.Add("check-swift-windows-x86_64")
    if (!${skip-test-optimized}) {
        $SWIFT_TEST_TARGETS.Add("check-swift-optimize-windows-x86_64")
    }
} else {
    $SWIFT_TEST_TARGETS.Add("check-swift-all-windows-x86_64")
    if (!${skip-test-optimized}) {
        $SWIFT_TEST_TARGETS.Add("check-swift-all-optimize-windows-x86_64")
    }
}
Write-Host "Building the standard library for: ${SWIFT_STDLIB_TARGETS}"
Write-Host "Running Swift tests for: ${SWIFT_TEST_TARGETS}"
Write-Host

[System.Collections.ArrayList]$COMMON_CMAKE_OPTIONS = @(
    "-G", "${cmake-generator}"
)

$COMMON_C_FLAGS=""
$COMMON_CXX_FLAGS=""

if (${enable-asan}) {
    $COMMON_CMAKE_OPTIONS.Add('-DLLVM_USE_SANITIZER="Address"')
}

$HOST_CC = $Env:HOST_CC
if (!$HOST_CC) {
     $script:HOST_CC = $(cmd /C where clang)
}

if (!$HOST_CC) {
    Write-Host "Can't find clang.  Please install clang-3.5 or a later version."
    Exit
}

 $COMMON_CMAKE_OPTIONS.Add("-DCMAKE_C_COMPILER:PATH=`"${HOST_CC}`"")
 $COMMON_CMAKE_OPTIONS.Add("-DCMAKE_CXX_COMPILER:PATH=`"${HOST_CXX}`"")
    
switch -wildcard (${cmake-generator}) {
    "Ninja" {
        if (${verbose-build}) {
            ${build-args} = "${build-args} -v"
        }
        if (${build-jobs}) {
            ${build-args} = "${build-args} -j${build-jobs}"
        }
    }
    "Visual Studio *" {
        if (${verbose-build}) {
            ${build-args} = "${build-args} /v"
        }
        if (${build-jobs}) {
            ${build-args} = "${build-args} /maxcpucount:${build-jobs}"
        }
    }
}

if (${clang-compiler-version}) {
    $major,$minor,$patch =  ${clang-compiler-version}.Split(".")
    $COMMON_CMAKE_OPTIONS.Add("-DLLVM_VERSION_MAJOR:STRING=`"${major}`"")
    $COMMON_CMAKE_OPTIONS.Add("-DLLVM_VERSION_MINOR:STRING=`"${minor}`"")
    $COMMON_CMAKE_OPTIONS.Add("-DLLVM_VERSION_PATCH:STRING=`"${patch}`"")
}

function build_directory {
    param([string]$deployment_target, [string]$product)
    "${build-dir}/$product-$deployment_target"
}

function build_directory_bin {
    param([string]$deployment_target, [string]$product)
    $root = build_directory $deployment_target $product
    "$root/bin"
}

function is_cmake_release_build_type {
    param([string]$type) 
    ($type -eq "Release" -or $type -eq "RelWithDebInfo")
}

function common_cross_c_flags {
    "$COMMON_C_FLAGS"
    #todo android
}

function llvm_c_flags {
    $flags = common_cross_c_flags
    if (is_cmake_release_build_type(${llvm-build-type})) {
        $flags = $flags + " -fno-stack-protector"
    }
    $flags
}

function cmark_c_flags {
    $flags = common_cross_c_flags
    if (is_cmake_release_build_type(${cmark-build-type})) {
        $flags = $flags + " -fno-stack-protector"
    }
    $flags
}

function swift_c_flags {
    # Don�t pass common_cross_c_flags to Swift because CMake code in the Swift
    # project is itself aware of cross-compilation for the host tools and
    # standard library.
    $flags = "$COMMON_C_FLAGS"
     if (is_cmake_release_build_type(${swift-build-type})) {
        $flags = $flags + " -fno-stack-protector"
    }
    $flags
}

function cmake_config_opt {
    param([string]$product)
    $out = ""
    if (${cmake-generator} -match "Visual Studio") {
        # CMake automatically adds --target ALL_BUILD if we don't pass this.
        $out = "--target ZERO_CHECK "
        switch($product) {
            "cmark" { $out = $out + "--config ${cmark-build-type}"}
            "llvm" { $out = $out + "--config ${llvm-build-type}" }
            "swift" { $out = $out + "--config ${swift-build-type}" }                
            "lldb"  { $out = $out + "--config ${lldb-build-type}" }
            "llbuild" { $out = $out + "--config ${llbuild-build-type}" }
            "swiftpm" { $out = $out + "--config ${swiftpm-build-type}" }
            "foundation" { $out = $out + "--config ${foundation-build-type}" }
        }
    }
    $out
}

function should_build_perftestsuite {
    ${build-swift-perf-testsuite} -eq $true
}



function set_swiftpm_bootstrap_command {
    param([string] $deployment_target)
    [System.Collections.ArrayList]$swiftpm_bootstrap_command=@()
    $swiftc_bin = "$(build_directory_bin $deployment_target "swift")/swiftc"
    $llbuild_bin = "$(build_directory_bin $deployment_target "llbuild")/swift-build-tool"
    if (!Test-Path $llbuild_bin) {
        Write-Host "Error: Cannot build swiftpm without llbuild (swift-build-tool)."
        Exit
    }
    
    [System.Collections.ArrayList]$swiftpm_bootstrap_command=@("${SWIFTPM_SOURCE_DIR}/Utilities/bootstrap")
    $swiftpm_bootstrap_command += $script:swiftpm_bootstrap_options
    if (${verbose-build}) {
        $swiftpm_bootstrap_command += "-v"
    }
    
    $swiftpm_bootstrap_command += "--swiftc=`"$swiftc_bin`""
    $swiftpm_bootstrap_command += "--sbt=`"$llbuild_bin`""
    $swiftpm_bootstrap_command += "--build=`"${build-dir}`""
    $script:swiftpm_bootstrap_command = $swiftpm_bootstrap_command
}

New-Item ${build-dir} -type directory -Force


#todo build ninja

#
# Configure and build each product
#
# Start with native deployment targets because the resulting tools are used during cross-compilation.

$all_products = ${native-tools-deployment-targets}
$all_products += ${cross-tools-deployment-targets}

foreach ($deployment_target in $all_products) {
    set_deployment_target_based_options($deployment_target)
    #TODO Compiler Vendor handling 
    
    [System.Collections.ArrayList]$llvm_cmake_options += @(
        "-DCMAKE_INSTALL_PREFIX:PATH=`"${install-prefix}`"",
        "-DINTERNAL_INSTALL_PREFIX=`"local`""
    )

    if (${clang-compiler-version}) {
        $llvm_cmake_options += @(
            "-DCLANG_REPOSITORY_STRING=`"${clang-compiler-version}`""
        )
        $swift_cmake_options += @(
            "-DCLANG_COMPILER_VERSION=`"${clang-compiler-version}`"",
            "-DSWIFT_COMPILER_VERSION=`"${swift-compiler-version}`""
        )
    }

    if (${swift-compiler-version}) {
        $swift_cmake_options += @(
             "-DSWIFT_COMPILER_VERSION=`"${swift-compiler-version}`""
        )
    }
    if (${enable-asan}) {
        $swift_cmake_options += @(
            "-DSWIFT_SOURCEKIT_USE_INPROC_LIBRARY:BOOL=TRUE"
        )
    }

    if (${extra-swift-args}) {
        $swift_cmake_options += @(
            "-DSWIFT_EXPERIMENTAL_EXTRA_REGEXP_FLAGS=`"${extra-swift-args}`""
        )
    }

    if (should_build_perftestsuite) {
       $swift_cmake_options += @(
            "-DSWIFT_INCLUDE_PERF_TESTSUITE=YES"
        ) 
    }

     $swift_cmake_options += @(
        "-DSWIFT_AST_VERIFIER:BOOL=$(true_false ${swift-enable-ast-verifier})",
        "-DSWIFT_VERIFY_ALL:BOOL=$(true_false ${sil-verify-all})",
        "-DSWIFT_RUNTIME_ENABLE_DTRACE:BOOL=$(true_false ${swift-runtime-enable-dtrace})",
        "-DSWIFT_RUNTIME_ENABLE_LEAK_CHECKER:BOOL=$(true_false ${swift-runtime-enable-leak-checker})"
    )


    foreach ($product in $PRODUCTS) {
        $skip_build = $False
        $build_dir = build_directory $deployment_target $product
        [System.Collections.ArrayList]$build_targets = @("all")
        [System.Collections.ArrayList]$cmake_options = @()
        $cmake_options += $COMMON_CMAKE_OPTIONS
        if (${use-gold-linker}) {
            Write-Host "$product using gold linker"
            if ($product -ne "swift") {
                # All other projects override the linker flags to add in
                # gold linker support.
                $cmake_options += @(
                    "-DCMAKE_EXE_LINKER_FLAGS:STRING=`"-fuse-ld=gold`"",
                    "-DCMAKE_SHARED_LINKER_FLAGS:STRING=`"-fuse-ld=gold`""
                ) 
            }
        } else {
            Write-Host "$product using standard linker"
        }

        $PRODUCT_UPPER = $product.ToString().ToUpperInvariant()

        $llvm_build_dir = build_directory $deployment_target "llvm"
        $module_cache="$build_dir/module-cache"
        $swift_cmake_options += @(
            "-DCMAKE_INSTALL_PREFIX:PATH=`"${install-prefix}`"",
            "-DLLVM_CONFIG:PATH=`"$(build_directory_bin $deployment_target "llvm")/llvm-config`"",
            "-D${PRODUCT_UPPER}_PATH_TO_CLANG_SOURCE:PATH=`"$CLANG_SOURCE_DIR`"",
            "-D${PRODUCT_UPPER}_PATH_TO_CLANG_BUILD:PATH=`"${llvm_build_dir}`"".
            "-D${PRODUCT_UPPER}_PATH_TO_LLVM_SOURCE:PATH=`"${LLVM_SOURCE_DIR}`"",
            "-D${PRODUCT_UPPER}_PATH_TO_LLVM_BUILD:PATH=`"${llvm_build_dir}`"",
            "-D${PRODUCT_UPPER}_PATH_TO_CMARK_SOURCE:PATH=`"${CMARK_SOURCE_DIR}`"",
            "-D${PRODUCT_UPPER}_PATH_TO_CMARK_BUILD:PATH=`"$(build_directory $deployment_target "cmark")`"",
            "-D${PRODUCT_UPPER}_CMARK_LIBRARY_DIR:PATH=`"$(build_directory $deployment_target "cmark")/src`""
        )

        switch($product) {
            "cmark" {
                $cmake_options += "-DCMAKE_BUILD_TYPE:STRING=`"${LLVM_BUILD_TYPE}`""
                $cmake_options += $cmark_cmake_options
                $cmake_options += "${CMARK_SOURCE_DIR}"
                $skip_build = ${skip-build-cmark}
                $build_targets = @("all")
            }

            "llvm" {
                if (!${build-llvm}) {
                    $build_targets = @("clean")
                }
                if (${skip-build-llvm}) {
                    # We can't skip the build completely because the standalone
                    # build of Swift depend on these.
                    $build_targets=@("llvm-config","llvm-tblgen","clang-headers")
                }
                 # Note: we set the variable:
                #
                # LLVM_TOOL_SWIFT_BUILD
                #
                # below because this script builds swift separately, and people
                # often have reasons to symlink the swift directory into
                # llvm/tools, e.g. to build LLDB.
               $cmake_options += @(
                    "-DCMAKE_C_FLAGS=`"$(llvm_c_flags($deployment_target))`"",
                    "-DCMAKE_CXX_FLAGS=`"$(llvm_c_flags($deployment_target))`"",
                    "-DCMAKE_BUILD_TYPE:STRING=`"${llvm-build-type}`"",
                    "-DLLVM_ENABLE_ASSERTIONS:BOOL=$(true_false(${llvm-enable-assertions} ))",
                    "-DLLVM_TOOL_SWIFT_BUILD:BOOL=NO",
                    "-DLLVM_TARGETS_TO_BUILD=`"${LLVM_TARGETS_TO_BUILD}`"",
                    "-DLLVM_INCLUDE_TESTS:BOOL=$(true_false(${source-tree-includes-tests}))",
                    "-LLVM_INCLUDE_DOCS:BOOL=TRUE")
                $cmake_options += $llvm_cmake_options
                $cmake_options += "`"$LLVM_SOURCE_DIR`""
                
                if (is_cross_tools_deployment_target($deployment_target)) {
                    $cmake_options += @(
                        "-DLLVM_TABLEGEN=$(build_directory "macosx-x86_64" "llvm")/bin/llvm-tblgen",
                        "-DCLANG_TABLEGEN=$(build_directory "macosx-x86_64" "llvm")/bin/clang-tblgen"
                    )
                }

            }

            "swift" {
                $cmake_options += @()
                $cmake_options = $COMMON_CMAKE_OPTIONS
                if (${use-gold-linker}) {
                    $cmake_options += "-DSWIFT_ENABLE_GOLD_LINKER=TRUE"
                }

                $native_llvm_tools_path=""
                $native_clang_tools_path=""
                $native_swift_tools_path=""
                #TODO: cross compile deploy target

                $build_tests_this_time = ${source-tree-includes-tests}

                # Command-line parameters override any autodetection that we
                # might have done.
                if (${native-llvm-tools-path}) {
                    $native_llvm_tools_path = ${native-llvm-tools-path}
                }

                if (${native-clang-tools-path}) {
                    $native_clang_tools_path = ${native-clang-tools-path}
                }

                if (${native-swift-tools-path}) {
                    $native_swift_tools_path = ${native-swift-tools-path}
                }

                if (!${build-llvm}) {
                    $cmake_options += @(
                        "-DLLVM_TOOLS_BINARY_DIR:PATH=/tmp/dummy",
                        "-DLLVM_LIBRARY_DIR:PATH=`"${build_dir}`"",
                        "-DLLVM_MAIN_INCLUDE_DIR:PATH=/tmp/dummy",
                        "-DLLVM_BINARY_DIR:PATH=`"$(build_directory $deployment_target "llvm")`"",
                        "-DLLVM_MAIN_SRC_DIR:PATH=`"${LLVM_SOURCE_DIR}`""
                    )
                }

                 $cmake_options += @(
                    "-DCMAKE_C_FLAGS=`"$(swift_c_flags $deployment_target)`"",
                    "-DCMAKE_CXX_FLAGS=`"$(swift_c_flags $deployment_target)`"",
                    "-DCMAKE_BUILD_TYPE:STRING=`"${swift-build-type}`"",
                    "-DLLVM_ENABLE_ASSERTIONS:BOOL=$(true_false ${swift-enable-assertions})",
                    "-DSWIFT_STDLIB_BUILD_TYPE:STRING=`"${swift-stdlib-build-type}`"",
                    "-DSWIFT_STDLIB_ASSERTIONS:BOOL=$(true_false ${swift-stdlib-enable-assertions})",
                    "-DSWIFT_NATIVE_LLVM_TOOLS_PATH:STRING=`"${native_llvm_tools_path}`"",
                    "-DSWIFT_NATIVE_CLANG_TOOLS_PATH:STRING=`"${native_clang_tools_path}`"",
                    "-DSWIFT_NATIVE_SWIFT_TOOLS_PATH:STRING=`"${native_swift_tools_path}`"",
                    "-DSWIFT_BUILD_TOOLS:BOOL=$(true_false ${build-swift-tools})",
                    "-DSWIFT_BUILD_STDLIB:BOOL=$(true_false ${build-swift-stdlib})",
                    "-DSWIFT_BUILD_SDK_OVERLAY:BOOL=$(true_false ${build-swift-sdk-overlay})",
                    "-DSWIFT_BUILD_STATIC_STDLIB:BOOL=$(true_false ${build-swift-static-stdlib})",
                    "-DSWIFT_BUILD_EXAMPLES:BOOL=$(true_false ${build-swift-examples} )",
                    "-DSWIFT_INCLUDE_TESTS:BOOL=$(true_false ${build_tests_this_time})",
                    "-DSWIFT_INSTALL_COMPONENTS:STRING=`"`"",
                    "-DSWIFT_EMBED_BITCODE_SECTION:BOOL=$(true_false ${embed-bitcode-section})"
                )
                $cmake_options += $swift_cmake_options
                $cmake_options += "`"$SWIFT_SOURCE_DIR`""

                $build_targets = @("all")
                $build_targets += $SWIFT_STDLIB_TARGETS
                if (should_build_perftestsuite) {
                    $build_targets+= "benchmark-swift"
                }
                
                $skip_build=${skip-build-swift}


            }

            "lldb" {
                Write-Host "LLdb not implemented"
            }

            "llbuild" {
               $cmake_options = @()
               $cmake_options += @(
                    "-DCMAKE_INSTALL_PREFIX:PATH=`"${install-prefix}`"",
                    "-DLIT_EXECUTABLE:PATH=`"${LLVM_SOURCE_DIR}/utils/lit/lit.py`"",
                    "-DFILECHECK_EXECUTABLE:PATH=`"$(build_directory_bin $deployment_target "llvm")/FileCheck`"",
                    "-DCMAKE_BUILD_TYPE:STRING=`"${lldb-build-type}`"",
                    "-DLLVM_ENABLE_ASSERTIONS:BOOL=$(true_false ${llbuild-enable-assertions})",
                    "`"${LLBUILD_SOURCE_DIR}`""
                )
            }

            "swiftpm" {
                set_swiftpm_bootstrap_command($deployment_target)
                $($swiftpm_bootstrap_command)
            }

            "foundation" {
                Write-Host "foundation not implemented"
            }
        }

        Remove-Item -Recurse -Force $module_cache
        New-Item $module_cache -type directory
        
         # Compute the generator output file to check for, to determine if we
        # must reconfigure. We only handle Ninja for now.
        #
        # This is important for ensuring that if a CMake configuration fails in
        # CI, that we will still be willing to rerun the configuration process.
        $generator_output_path=""
        if (${cmake-generator}  -eq "Ninja" ) {
            $generator_output_path="${build_dir}/build.ninja"
        }

        # Configure if necessary.
        if (($reconfigure -or  ! (Test-Path "${build_dir}/CMakeCache.txt")) -or ( $generator_output_path -and  ! (Test-Path $generator_output_path))) {
            New-Item $build_dir -type directory   
            Set-Location -Path $build_dir     
            &"$cmake" $cmake_options ${user-config-args}
        }

        # Build.
        if (! $skip_build ) {
            $("`"$cmake`" --build `"$build_dir`" $(cmake_config_opt($product)) -- ${build-args} $build_targets")
        }

    }

}
























<#
#!/usr/bin/env bash
#===--- build-script-impl - Implementation details of build-script ---------===#
#
## This source file is part of the Swift.org open source project
##
## Copyright (c) 2014 - 2015 Apple Inc. and the Swift project authors
## Licensed under Apache License v2.0 with Runtime Library Exception
##
## See http://swift.org/LICENSE.txt for license information
## See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
#
#===------------------------------------------------------------------------===#

#
# This script is an implementation detail of other build scripts and should not
# be called directly.
#
# Note: This script will NOT auto-clean before building.
#

set -o pipefail
set -e

umask 0022



LLVM_TARGETS_TO_BUILD="X86;ARM;AArch64"

#
# End of configurable options.
#

# Declare the set of known settings along with each one's description
#
# If you add a user-settable variable, add it to this list.
#
# A default value of "" indicates that the corresponding variable
# will remain unset unless set explicitly.
#
# skip-* parameters do not affect the configuration (CMake parameters).
# You can turn them on and off in different invocations of the script for the
# same build directory.
#
# build-* parameters affect the CMake configuration (enable/disable those
# components).
#
# Each variable name is re-exported into this script in uppercase, where dashes
# are substituded by underscores. For example, `swift-install-components` is
# referred to as `SWIFT_INSTALL_COMPONENTS` in the remainder of this script.
KNOWN_SETTINGS=(
    # name                      default          description
    build-args                  ""               "arguments to the build tool; defaults to -j8 when CMake generator is \"Unix Makefiles\""
    build-dir                   ""               "out-of-tree build directory; default is in-tree. **This argument is required**"
    darwin-xcrun-toolchain      "default"        "the name of the toolchain to use on Darwin"
    build-ninja                 ""               "build the Ninja tool"
    cmark-build-type            "Debug"          "the CMake build variant for CommonMark (Debug, RelWithDebInfo, Release, MinSizeRel).  Defaults to Debug."
    lldb-extra-cmake-args       ""               "extra command line args to pass to lldb cmake"
    lldb-test-with-curses       ""               "run test lldb test runner using curses terminal control"
    lldb-no-debugserver         ""               "delete debugserver after building it, and don't try to codesign it"
    lldb-use-system-debugserver ""               "don't try to codesign debugserver, and use the system's debugserver instead"
    llvm-build-type             "Debug"          "the CMake build variant for LLVM and Clang (Debug, RelWithDebInfo, Release, MinSizeRel).  Defaults to Debug."
    llvm-enable-assertions      "1"              "enable assertions in LLVM and Clang"
    swift-build-type            "Debug"          "the CMake build variant for Swift"
    swift-enable-assertions     "1"              "enable assertions in Swift"
    swift-stdlib-build-type     "Debug"          "the CMake build variant for Swift"
    swift-stdlib-enable-assertions "1"           "enable assertions in Swift"
    lldb-build-type             "Debug"          "the CMake build variant for LLDB"
    llbuild-build-type          "Debug"          "the CMake build variant for llbuild"
    foundation-build-type       "Debug"          "the build variant for Foundation"
    llbuild-enable-assertions   "1"              "enable assertions in llbuild"
    enable-asan                 ""               "enable AddressSanitizer"
    cmake                       ""               "path to the cmake binary"
    distcc                      ""               "use distcc in pump mode"
    user-config-args            ""               "User-supplied arguments to cmake when used to do configuration"
    cmake-generator             "Unix Makefiles" "kind of build system to generate; see output of 'cmake --help' for choices"
    verbose-build               ""               "print the commands executed during the build"
    install-prefix              ""               "installation prefix"
    install-destdir             ""               "the path to use as the filesystem root for the installation"
    install-symroot             ""               "the path to install debug symbols into"
    swift-install-components    ""               "a semicolon-separated list of Swift components to install"
    llvm-install-components    ""                "a semicolon-separated list of LLVM components to install"
    installable-package         ""               "the path to the archive of the installation directory"
    test-installable-package    ""               "whether to run post-packaging tests on the produced package"
    symbols-package             ""               "the path to the archive of the symbols directory"
    show-sdks                   ""               "print installed Xcode and SDK versions"
    reconfigure                 ""               "force a CMake configuration run even if CMakeCache.txt already exists"
    swift-sdks                  ""               "build target binaries only for specified SDKs (semicolon-separated list)"
    swift-primary-variant-sdk   ""               "default SDK for target binaries"
    swift-primary-variant-arch  ""               "default arch for target binaries"
    skip-ios                    ""               "set to skip everything iOS-related"
    skip-tvos                   ""               "set to skip everything tvOS-related"
    skip-watchos                ""               "set to skip everything watchOS-related"
    skip-build                  ""               "set to skip building anything"
    skip-build-cmark            ""               "set to skip building CommonMark"
    skip-build-llvm             ""               "set to skip building LLVM/Clang"
    skip-build-swift            ""               "set to skip building Swift"
    skip-build-osx              ""               "set to skip building Swift stdlibs for OSX"
    skip-build-ios              ""               "set to skip building Swift stdlibs for iOS"
    skip-build-ios-device       ""               "set to skip building Swift stdlibs for iOS devices (i.e. build simulators only)"
    skip-build-ios-simulator    ""               "set to skip building Swift stdlibs for iOS simulators (i.e. build devices only)"
    skip-build-tvos             ""               "set to skip building Swift stdlibs for tvOS"
    skip-build-tvos-device      ""               "set to skip building Swift stdlibs for tvOS devices (i.e. build simulators only)"
    skip-build-tvos-simulator   ""               "set to skip building Swift stdlibs for tvOS simulators (i.e. build devices only)"
    skip-build-watchos          ""               "set to skip building Swift stdlibs for Apple watchOS"
    skip-build-watchos-device   ""               "set to skip building Swift stdlibs for Apple watchOS devices (i.e. build simulators only)"
    skip-build-watchos-simulator ""              "set to skip building Swift stdlibs for Apple watchOS simulators (i.e. build devices only)"
    skip-build-lldb             ""               "set to skip building LLDB"
    skip-build-llbuild          ""               "set to skip buildling llbuild"
    skip-build-swiftpm          ""               "set to skip buildling swiftpm"
    skip-build-xctest           ""               "set to skip buildling xctest"
    skip-build-foundation       ""               "set to skip buildling foundation"
    skip-test-cmark             ""               "set to skip testing CommonMark"
    skip-test-lldb              ""               "set to skip testing lldb"
    skip-test-swift             ""               "set to skip testing Swift"
    skip-test-llbuild           ""               "set to skip testing llbuild"
    skip-test-swiftpm           ""               "set to skip testing swiftpm"
    skip-test-xctest            ""               "set to skip testing xctest"
    skip-test-foundation        ""               "set to skip testing foundation"
    skip-test-osx               ""               "set to skip testing Swift stdlibs for OSX"
    skip-test-ios               ""               "set to skip testing Swift stdlibs for iOS"
    skip-test-ios-simulator     ""               "set to skip testing Swift stdlibs for iOS simulators (i.e. test devices only)"
    skip-test-tvos              ""               "set to skip testing Swift stdlibs for tvOS"
    skip-test-tvos-simulator    ""               "set to skip testing Swift stdlibs for tvOS simulators (i.e. test devices only)"
    skip-test-watchos           ""               "set to skip testing Swift stdlibs for Apple watchOS"
    skip-test-watchos-simulator  ""              "set to skip testing Swift stdlibs for Apple watchOS simulators (i.e. test devices only)"
    skip-test-validation        ""               "set to skip validation test suite"
    skip-test-optimized         ""               "set to skip testing the test suite in optimized mode"
    stress-test-sourcekit       ""               "set to run the stress-SourceKit target"
    xcode-ide-only              ""               "set to configure Xcode project for IDE use only, not building"
    workspace                   "${HOME}/src"    "source directory containing llvm, clang, swift"
    enable-llvm-assertions      "1"              "set to enable llvm assertions"
    build-llvm                  "1"              "set to 1 to build LLVM and Clang"
    build-swift-tools           "1"              "set to 1 to build Swift host tools"
    build-swift-stdlib          "1"              "set to 1 to build the Swift standard library"
    build-swift-sdk-overlay     "1"              "set to 1 to build the Swift SDK overlay"
    build-swift-static-stdlib   "0"              "set to 1 to build static versions of the Swift standard library and SDK overlay"
    build-swift-examples        "1"              "set to 1 to build examples"
    build-swift-perf-testsuite  "0"              "set to 1 to build perf test suite"
    source-tree-includes-tests  "1"              "set to 0 to allow the build to proceed when 'test' directory is missing (required for B&I builds)"
    native-llvm-tools-path      ""               "directory that contains LLVM tools that are executable on the build machine"
    native-clang-tools-path     ""               "directory that contains Clang tools that are executable on the build machine"
    native-swift-tools-path     ""               "directory that contains Swift tools that are executable on the build machine"
    compiler-vendor             "none"           "compiler vendor name [none,apple]"
    swift-compiler-version      ""               "string that indicates a compiler version for Swift"
    clang-compiler-version      ""               "string that indicates a compiler version for Clang"
    embed-bitcode-section       "0"              "embed an LLVM bitcode section in stdlib/overlay binaries for supported platforms"
    darwin-crash-reporter-client ""              "whether to enable CrashReporter integration"
    darwin-stdlib-install-name-dir ""            "the directory of the install_name for standard library dylibs"
    install-cmark               ""               "whether to install cmark"
    install-swift               ""               "whether to install Swift"
    install-lldb                ""               "whether to install LLDB"
    install-llbuild             ""               "whether to install llbuild"
    install-swiftpm             ""               "whether to install swiftpm"
    install-xctest              ""               "whether to install xctest"
    install-foundation          ""               "whether to install foundation"
    darwin-install-extract-symbols ""            "whether to extract symbols with dsymutil during installations"
    cross-compile-tools-deployment-targets ""    "space-separated list of targets to cross-compile host Swift tools for"
    skip-merge-lipo-cross-compile-tools ""       "set to skip running merge-lipo after installing cross-compiled host Swift tools"
    darwin-deployment-version-osx     "10.9"     "minimum deployment target version for OS X"
    darwin-deployment-version-ios     "7.0"      "minimum deployment target version for iOS"
    darwin-deployment-version-tvos    "9.0"      "minimum deployment target version for tvOS"
    darwin-deployment-version-watchos "2.0"      "minimum deployment target version for watchOS"

    extra-swift-args            ""               "Extra arguments to pass to swift modules which match regex. Assumed to be a flattened cmake list consisting of [module_regexp, args, module_regexp, args, ...]"
    sil-verify-all              "0"              "If enabled, run the sil verifier be run after every SIL pass"
    swift-enable-ast-verifier   "1"              "If enabled, and the assertions are enabled, the built Swift compiler will run the AST verifier every time it is invoked"
    swift-runtime-enable-dtrace "0"              "Enable runtime dtrace support"
    swift-runtime-enable-leak-checker   "0"              "Enable leaks checking routines in the runtime"
    use-gold-linker             ""               "Enable using the gold linker"
    darwin-toolchain-bundle-identifier ""        "CFBundleIdentifier for xctoolchain info plist"
    darwin-toolchain-display-name      ""        "Display Name for xctoolcain info plist"
    darwin-toolchain-name              ""        "Directory name for xctoolchain"
    darwin-toolchain-version           ""        "Version for xctoolchain info plist and installer pkg"
    darwin-toolchain-application-cert  ""        "Application Cert name to codesign xctoolchain"
    darwin-toolchain-installer-cert    ""        "Installer Cert name to create installer pkg"
    darwin-toolchain-installer-package ""        "The path to installer pkg"
    build-jobs ""                                "The number of parallel build jobs to use"

)

function toupper() {
    echo "$@" | tr '[:lower:]' '[:upper:]'
}

function to_varname() {
    toupper "${1//-/_}"
}

function get_make_parallelism() {
    case "$(uname -s)" in
        Linux)
            nproc
            ;;

        Darwin)
            sysctl -n hw.activecpu
            ;;

        *)
            echo 8
            ;;
    esac
}

function get_dsymutil_parallelism() {
    get_make_parallelism
}

function set_lldb_build_mode() {
    LLDB_BUILD_MODE="CustomSwift-${LLDB_BUILD_TYPE}"
}

function set_deployment_target_based_options() {
    llvm_cmake_options=()
    swift_cmake_options=()
    cmark_cmake_options=()
    swiftpm_bootstrap_options=()

    case $deployment_target in
        linux-x86_64)
            SWIFT_HOST_VARIANT_ARCH="x86_64"
            ;;
        freebsd-x86_64)
            SWIFT_HOST_VARIANT_ARCH="x86_64"
            ;;
        macosx-* | iphoneos-* | iphonesimulator-* | \
          appletvos-* | appletvsimulator-* | \
            watchos-* | watchsimulator-*)
            case ${deployment_target} in
                macosx-x86_64)
                    xcrun_sdk_name="macosx"
                    llvm_host_triple="x86_64-apple-macosx${DARWIN_DEPLOYMENT_VERSION_OSX}"
                    llvm_target_arch=""
                    cmake_osx_deployment_target="${DARWIN_DEPLOYMENT_VERSION_OSX}"
                    cmark_cmake_options=(
                        -DCMAKE_C_FLAGS="$(cmark_c_flags $deployment_target)"
                        -DCMAKE_CXX_FLAGS="$(cmark_c_flags $deployment_target)"
                        -DCMAKE_OSX_SYSROOT:PATH="$(xcrun --sdk $xcrun_sdk_name --show-sdk-path)"
                        -DCMAKE_OSX_DEPLOYMENT_TARGET="${cmake_osx_deployment_target}"
                    )
                    swiftpm_bootstrap_options=(
                        --sysroot="$(xcrun --sdk $xcrun_sdk_name --show-sdk-path)"
                    )
                    ;;
                iphonesimulator-i386)
                    xcrun_sdk_name="iphonesimulator"
                    llvm_host_triple="i386-apple-ios${DARWIN_DEPLOYMENT_VERSION_IOS}"
                    llvm_target_arch="X86"
                    cmake_osx_deployment_target=""
                    cmark_cmake_options=(
                        -DCMAKE_C_FLAGS="$(cmark_c_flags $deployment_target)"
                        -DCMAKE_CXX_FLAGS="$(cmark_c_flags $deployment_target)"
                        -DCMAKE_OSX_SYSROOT:PATH="$(xcrun --sdk $xcrun_sdk_name --show-sdk-path)"
                    )
                    swift_cmake_options=(
                        -DSWIFT_HOST_VARIANT="iphonesimulator"
                        -DSWIFT_HOST_VARIANT_SDK="IOS_SIMULATOR"
                        -DSWIFT_HOST_VARIANT_ARCH="i386"
                    )
                    ;;
                iphonesimulator-x86_64)
                    xcrun_sdk_name="iphonesimulator"
                    llvm_host_triple="x86_64-apple-ios${DARWIN_DEPLOYMENT_VERSION_IOS}"
                    llvm_target_arch="X86"
                    cmake_osx_deployment_target=""
                    cmark_cmake_options=(
                        -DCMAKE_C_FLAGS="$(cmark_c_flags $deployment_target)"
                        -DCMAKE_CXX_FLAGS="$(cmark_c_flags $deployment_target)"
                        -DCMAKE_OSX_SYSROOT:PATH="$(xcrun --sdk $xcrun_sdk_name --show-sdk-path)"
                    )
                    swift_cmake_options=(
                        -DSWIFT_HOST_VARIANT="iphonesimulator"
                        -DSWIFT_HOST_VARIANT_SDK="IOS_SIMULATOR"
                        -DSWIFT_HOST_VARIANT_ARCH="x86_64"
                    )
                    ;;
                iphoneos-armv7)
                    xcrun_sdk_name="iphoneos"
                    llvm_host_triple="armv7-apple-ios${DARWIN_DEPLOYMENT_VERSION_IOS}"
                    llvm_target_arch="ARM"
                    cmake_osx_deployment_target=""
                    cmark_cmake_options=(
                        -DCMAKE_C_FLAGS="$(cmark_c_flags $deployment_target)"
                        -DCMAKE_CXX_FLAGS="$(cmark_c_flags $deployment_target)"
                        -DCMAKE_OSX_SYSROOT:PATH="$(xcrun --sdk $xcrun_sdk_name --show-sdk-path)"
                    )
                    swift_cmake_options=(
                        -DSWIFT_HOST_VARIANT="iphoneos"
                        -DSWIFT_HOST_VARIANT_SDK="IOS"
                        -DSWIFT_HOST_VARIANT_ARCH="armv7"
                    )
                    ;;
                iphoneos-arm64)
                    xcrun_sdk_name="iphoneos"
                    llvm_host_triple="arm64-apple-ios${DARWIN_DEPLOYMENT_VERSION_IOS}"
                    llvm_target_arch="AArch64"
                    cmake_osx_deployment_target=""
                    cmark_cmake_options=(
                        -DCMAKE_C_FLAGS="$(cmark_c_flags $deployment_target)"
                        -DCMAKE_CXX_FLAGS="$(cmark_c_flags $deployment_target)"
                        -DCMAKE_OSX_SYSROOT:PATH="$(xcrun --sdk $xcrun_sdk_name --show-sdk-path)"
                    )
                    swift_cmake_options=(
                        -DSWIFT_HOST_VARIANT="iphoneos"
                        -DSWIFT_HOST_VARIANT_SDK="IOS"
                        -DSWIFT_HOST_VARIANT_ARCH="arm64"
                    )
                    ;;
                appletvsimulator-x86_64)
                    xcrun_sdk_name="appletvsimulator"
                    llvm_host_triple="x86_64-apple-tvos${DARWIN_DEPLOYMENT_VERSION_TVOS}"
                    llvm_target_arch="X86"
                    cmake_osx_deployment_target=""
                    cmark_cmake_options=(
                        -DCMAKE_C_FLAGS="$(cmark_c_flags $deployment_target)"
                        -DCMAKE_CXX_FLAGS="$(cmark_c_flags $deployment_target)"
                        -DCMAKE_OSX_SYSROOT:PATH="$(xcrun --sdk $xcrun_sdk_name --show-sdk-path)"
                    )
                    swift_cmake_options=(
                        -DSWIFT_HOST_VARIANT="appletvsimulator"
                        -DSWIFT_HOST_VARIANT_SDK="TVOS_SIMULATOR"
                        -DSWIFT_HOST_VARIANT_ARCH="x86_64"
                    )
                    ;;
                appletvos-arm64)
                    xcrun_sdk_name="appletvos"
                    llvm_host_triple="arm64-apple-tvos${DARWIN_DEPLOYMENT_VERSION_TVOS}"
                    llvm_target_arch="AArch64"
                    cmake_osx_deployment_target=""
                    cmark_cmake_options=(
                        -DCMAKE_C_FLAGS="$(cmark_c_flags $deployment_target)"
                        -DCMAKE_CXX_FLAGS="$(cmark_c_flags $deployment_target)"
                        -DCMAKE_OSX_SYSROOT:PATH="$(xcrun --sdk $xcrun_sdk_name --show-sdk-path)"
                    )
                    swift_cmake_options=(
                        -DSWIFT_HOST_VARIANT="appletvos"
                        -DSWIFT_HOST_VARIANT_SDK="TVOS"
                        -DSWIFT_HOST_VARIANT_ARCH="arm64"
                    )
                    ;;
                watchsimulator-i386)
                    xcrun_sdk_name="watchsimulator"
                    llvm_host_triple="i386-apple-watchos${DARWIN_DEPLOYMENT_VERSION_WATCHOS}"
                    llvm_target_arch="X86"
                    cmake_osx_deployment_target=""
                    cmark_cmake_options=(
                        -DCMAKE_C_FLAGS="$(cmark_c_flags $deployment_target)"
                        -DCMAKE_CXX_FLAGS="$(cmark_c_flags $deployment_target)"
                        -DCMAKE_OSX_SYSROOT:PATH="$(xcrun --sdk $xcrun_sdk_name --show-sdk-path)"
                    )
                    swift_cmake_options=(
                        -DSWIFT_HOST_VARIANT="watchsimulator"
                        -DSWIFT_HOST_VARIANT_SDK="WATCHOS_SIMULATOR"
                        -DSWIFT_HOST_VARIANT_ARCH="i386"
                    )
                    ;;
                watchos-armv7k)
                    xcrun_sdk_name="watchos"
                    llvm_host_triple="armv7k-apple-watchos${DARWIN_DEPLOYMENT_VERSION_WATCHOS}"
                    llvm_target_arch="ARM"
                    cmake_osx_deployment_target=""
                    cmark_cmake_options=(
                        -DCMAKE_C_FLAGS="$(cmark_c_flags $deployment_target)"
                        -DCMAKE_CXX_FLAGS="$(cmark_c_flags $deployment_target)"
                        -DCMAKE_OSX_SYSROOT:PATH="$(xcrun --sdk $xcrun_sdk_name --show-sdk-path)"
                    )
                    swift_cmake_options=(
                        -DSWIFT_HOST_VARIANT="watchos"
                        -DSWIFT_HOST_VARIANT_SDK="WATCHOS"
                        -DSWIFT_HOST_VARIANT_ARCH="armv7k"
                    )
                    ;;
                *)
                    echo "Unknown deployment target"
                    exit 1
                    ;;
            esac

            native_llvm_build=$(build_directory macosx-x86_64 llvm)
            llvm_cmake_options=(
                -DCMAKE_OSX_DEPLOYMENT_TARGET:STRING="${cmake_osx_deployment_target}"
                -DCMAKE_OSX_SYSROOT:PATH="$(xcrun --sdk $xcrun_sdk_name --show-sdk-path)"
                -DLLVM_HOST_TRIPLE:STRING="${llvm_host_triple}"
            )
            swift_cmake_options=(
                "${swift_cmake_options[@]}"
                -DSWIFT_DARWIN_DEPLOYMENT_VERSION_OSX="${DARWIN_DEPLOYMENT_VERSION_OSX}"
                -DSWIFT_DARWIN_DEPLOYMENT_VERSION_IOS="${DARWIN_DEPLOYMENT_VERSION_IOS}"
                -DSWIFT_DARWIN_DEPLOYMENT_VERSION_TVOS="${DARWIN_DEPLOYMENT_VERSION_TVOS}"
                -DSWIFT_DARWIN_DEPLOYMENT_VERSION_WATCHOS="${DARWIN_DEPLOYMENT_VERSION_WATCHOS}"
            )

            if [[ "${llvm_target_arch}" ]] ; then
                llvm_cmake_options=(
                    "${llvm_cmake_options[@]}"
                    -DLLVM_TARGET_ARCH="${llvm_target_arch}"
                )
            fi

            ;;
        *)
            echo "Unknown compiler deployment target: $deployment_target"
            exit 1
            ;;
    esac

}

# Set up an "associative array" of settings for error checking, and set
# (or unset) each corresponding variable to its default value
# If the Mac's bash were not stuck in the past, we could "declare -A" an
# associative array, but instead we have to hack it by defining variables
# declare -A IS_KNOWN_SETTING
for ((i = 0; i < ${#KNOWN_SETTINGS[@]}; i += 3)); do
    setting="${KNOWN_SETTINGS[i]}"

    default_value="${KNOWN_SETTINGS[$((i+1))]}"

    varname="$(to_varname "${setting}")"    # upcase the setting name to get the variable
    eval "${varname}_IS_KNOWN_SETTING=1"

    if [[ "${default_value}" ]] ; then
        # For an explanation of the backslash see http://stackoverflow.com/a/9715377
        eval ${varname}=$\default_value
    else
        unset ${varname}
    fi
done

COMMAND_NAME="$(basename "$0")"

# Print instructions for using this script to stdout
usage() {
    echo "Usage: ${COMMAND_NAME} [--help|-h] [ --SETTING=VALUE | --SETTING VALUE | --SETTING ]*"
    echo
    echo "  Available settings. Each setting corresponds to a variable,"
    echo "  obtained by upcasing its name, in this script.  A variable"
    echo "  with no default listed here will be unset in the script if"
    echo "  not explicitly specified.  A setting passed in the 3rd form"
    echo "  will set its corresponding variable to \"1\"."
    echo

    setting_list="
 | |Setting| Default|Description
 | |-------| -------|-----------
"

    for ((i = 0; i < ${#KNOWN_SETTINGS[@]}; i += 3)); do
        setting_list+="\
 | |--${KNOWN_SETTINGS[i]}| ${KNOWN_SETTINGS[$((i+1))]}|${KNOWN_SETTINGS[$((i+2))]}
"
    done
    echo "${setting_list}" | column -x -s'|' -t
    echo
    echo "Note: when using the form --SETTING VALUE, VALUE must not begin "
    echo "      with a hyphen."
    echo "Note: the \"--release\" option creates a pre-packaged combination"
    echo "      of settings used by the buildbot."
    echo
    echo "Cross-compiling Swift host tools"
    echo "  When building cross-compiled tools, it first builds for the native"
    echo "  build host machine. Then it proceeds to build the specified cross-compile"
    echo "  targets. It currently builds the requested variants of stdlib each"
    echo "  time around, so once for the native build, then again each time for"
    echo "  the cross-compile tool targets."
    echo
    echo "  When installing cross-compiled tools, it first installs each target"
    echo "  arch into a separate subdirectory under install-destdir, since you"
    echo "  can cross-compile for multiple targets at the same time. It then runs"
    echo "  recursive-lipo to produce fat binaries by merging the cross-compiled"
    echo "  targets, installing the merged result into the expected location of"
    echo "  install-destdir. After that, any remaining steps to extract dsyms and"
    echo "  create an installable package operates on install-destdir as normal."
}

# Scan all command-line arguments
while [[ "$1" ]] ; do
    case "$1" in
        -h | --help )
            usage
            exit
            ;;

        --* )
            dashless="${1:2}"

            # drop suffix beginning with the first "="
            setting="${dashless%%=*}"

            # compute the variable to set
            varname="$(to_varname "${setting}")"

            # check to see if this is a known option
            known_var_name="${varname}_IS_KNOWN_SETTING"
            if [[ ! "${!known_var_name}" ]] ; then
                echo "Error: Unknown setting: ${setting}" 1>&2
                usage 1>&2
                exit 1
            fi

            # find the intended value
            if [[ "${dashless}" == *=* ]] ; then              # if there's an '=', the value
                value="${dashless#*=}"                        #   is everything after the first '='
            elif [[ "$2" ]] && [[ "${2:0:1}" != "-" ]] ; then # else if the next parameter exists
                value="$2"                                    #    but isn't  an option, use that
                shift
            else                                             # otherwise, the value is 1
                value=1
            fi

            # For explanation of backslash see http://stackoverflow.com/a/9715377
            eval ${varname}=$\value
            ;;

        *)
            usage
            exit 1
    esac
    shift
done

if [[ "$SKIP_BUILD" ]]; then
    SKIP_BUILD_CMARK=1
    SKIP_BUILD_LLVM=1
    SKIP_BUILD_SWIFT=1
    SKIP_BUILD_OSX=1
    SKIP_BUILD_IOS=1
    SKIP_BUILD_IOS_DEVICE=1
    SKIP_BUILD_IOS_SIMULATOR=1
    SKIP_BUILD_TVOS=1
    SKIP_BUILD_TVOS_DEVICE=1
    SKIP_BUILD_TVOS_SIMULATOR=1
    SKIP_BUILD_WATCHOS=1
    SKIP_BUILD_WATCHOS_DEVICE=1
    SKIP_BUILD_WATCHOS_SIMULATOR=1
    SKIP_BUILD_LLDB=1
    SKIP_BUILD_LLBUILD=1
    SKIP_BUILD_SWIFTPM=1
    SKIP_BUILD_XCTEST=1
    SKIP_BUILD_FOUNDATION=1
fi

if [[ "$SKIP_IOS" ]] ; then
    SKIP_BUILD_IOS=1
    SKIP_BUILD_IOS_DEVICE=1
    SKIP_BUILD_IOS_SIMULATOR=1
    SKIP_TEST_IOS=1
    SKIP_TEST_IOS_SIMULATOR=1
fi

if [[ "$SKIP_TVOS" ]] ; then
    SKIP_BUILD_TVOS=1
    SKIP_BUILD_TVOS_DEVICE=1
    SKIP_BUILD_TVOS_SIMULATOR=1
    SKIP_TEST_TVOS=1
    SKIP_TEST_TVOS_SIMULATOR=1
fi

if [[ "$SKIP_WATCHOS" ]] ; then
    SKIP_BUILD_WATCHOS=1
    SKIP_BUILD_WATCHOS_DEVICE=1
    SKIP_BUILD_WATCHOS_SIMULATOR=1
    SKIP_TEST_WATCHOS=1
    SKIP_TEST_WATCHOS_SIMULATOR=1
fi

if [[ "$SKIP_BUILD_IOS" ]] ; then
    SKIP_BUILD_IOS=1
    SKIP_BUILD_IOS_DEVICE=1
    SKIP_BUILD_IOS_SIMULATOR=1
    SKIP_TEST_IOS=1
    SKIP_TEST_IOS_SIMULATOR=1
fi

if [[ "$SKIP_BUILD_TVOS" ]] ; then
    SKIP_BUILD_TVOS=1
    SKIP_BUILD_TVOS_DEVICE=1
    SKIP_BUILD_TVOS_SIMULATOR=1
    SKIP_TEST_TVOS=1
    SKIP_TEST_TVOS_SIMULATOR=1
fi

if [[ "$SKIP_BUILD_WATCHOS" ]] ; then
    SKIP_BUILD_WATCHOS=1
    SKIP_BUILD_WATCHOS_DEVICE=1
    SKIP_BUILD_WATCHOS_SIMULATOR=1
    SKIP_TEST_WATCHOS=1
    SKIP_TEST_WATCHOS_SIMULATOR=1
fi

if [[ "$SKIP_BUILD_IOS_DEVICE" ]] ; then
    SKIP_BUILD_IOS_DEVICE=1
fi

if [[ "$SKIP_BUILD_TVOS_DEVICE" ]] ; then
    SKIP_BUILD_TVOS_DEVICE=1
fi

if [[ "$SKIP_BUILD_WATCHOS_DEVICE" ]] ; then
    SKIP_BUILD_WATCHOS_DEVICE=1
fi

if [[ "$SKIP_BUILD_IOS_SIMULATOR" ]] ; then
    SKIP_BUILD_IOS_SIMULATOR=1
    SKIP_TEST_IOS_SIMULATOR=1
fi

if [[ "$SKIP_BUILD_TVOS_SIMULATOR" ]] ; then
    SKIP_BUILD_TVOS_SIMULATOR=1
    SKIP_TEST_TVOS_SIMULATOR=1
fi

if [[ "$SKIP_BUILD_WATCHOS_SIMULATOR" ]] ; then
    SKIP_BUILD_WATCHOS_SIMULATOR=1
    SKIP_TEST_WATCHOS_SIMULATOR=1
fi

if [[ "$SKIP_TEST_IOS" ]] ; then
    SKIP_TEST_IOS_SIMULATOR=1
fi

if [[ "$SKIP_TEST_TVOS" ]] ; then
    SKIP_TEST_TVOS_SIMULATOR=1
fi

if [[ "$SKIP_TEST_WATCHOS" ]] ; then
    SKIP_TEST_WATCHOS_SIMULATOR=1
fi

if [[ "${CMAKE_GENERATOR}" == "Ninja" ]] && [[ -z "$(which ninja)" ]] ; then
    BUILD_NINJA=1
fi

# WORKSPACE, BUILD_DIR and INSTALLABLE_PACKAGE must be absolute paths
#case "${WORKSPACE}" in
#    /*) ;;
#    *)
#        echo "workspace must be an absolute path (was '${WORKSPACE}')"
#        exit 1
#        ;;
#esac
#case "${BUILD_DIR}" in
#    /*) ;;
#    "")
#        echo "the --build-dir option is required"
#        usage
#        exit 1
#        ;;
#    *)
#        echo "build-dir must be an absolute path (was '${BUILD_DIR}')"
#        exit 1
#        ;;
#esac
case "${INSTALLABLE_PACKAGE}" in
    /*) ;;
    "") ;;
    *)
        echo "installable-package must be an absolute path (was '${INSTALLABLE_PACKAGE}')"
        exit 1
        ;;
esac
case "${SYMBOLS_PACKAGE}" in
    /*) ;;
    "") ;;
    *)
        echo "symbols-package must be an absolute path (was '${SYMBOLS_PACKAGE}')"
        exit 1
        ;;
esac

# WORKSPACE must exist
if [ ! -e "$WORKSPACE" ] ; then
    echo "Workspace does not exist (tried $WORKSPACE)"
    exit 1
fi

function xcrun_find_tool() {
  xcrun --sdk macosx --toolchain "${DARWIN_XCRUN_TOOLCHAIN}" --find "$@"
}

function not() {
    if [[ ! "$1" ]] ; then
        echo 1
    fi
}

function true_false() {
    case "$1" in
        false | 0)
            echo "FALSE"
            ;;
        true | 1)
            echo "TRUE"
            ;;
        *)
            echo "true_false: unknown value: $1" >&2
            exit 1
            ;;
    esac
}

#
# Set default values for command-line parameters.
#

if [[ "${CMAKE}" == "" ]] ; then
    if [[ "$(uname -s)" == "Darwin" ]] ; then
        CMAKE="$(xcrun_find_tool cmake)"
    else
        CMAKE="$(which cmake || echo /usr/local/bin/cmake)"
    fi
fi

if [[ "${INSTALL_PREFIX}" == "" ]] ; then
    if [[ "$(uname -s)" == "Darwin" ]] ; then
        INSTALL_PREFIX="/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr"
    else
        INSTALL_PREFIX="/usr"
    fi
fi

if [[ "$(uname -s)" == "Darwin" ]] ; then
    TOOLCHAIN_PREFIX=$(echo ${INSTALL_PREFIX} | sed -E 's/\/usr$//')
fi

# A list of deployment targets to compile the Swift host tools for, in case when
# we can run the resulting binaries natively on the build machine.
NATIVE_TOOLS_DEPLOYMENT_TARGETS=()

# A list of deployment targets to cross-compile the Swift host tools for.
# We can't run the resulting binaries on the build machine.
CROSS_TOOLS_DEPLOYMENT_TARGETS=()

# Determine the native deployment target for the build machine, that will be
# used to jumpstart the standard library build when cross-compiling.
case "$(uname -s)" in
    Linux)
        NATIVE_TOOLS_DEPLOYMENT_TARGETS=(
            "linux-x86_64"
        )
        ;;

    Darwin)
        NATIVE_TOOLS_DEPLOYMENT_TARGETS=(
            "macosx-x86_64"
        )
        ;;

    FreeBSD)
        NATIVE_TOOLS_DEPLOYMENT_TARGETS=(
            "freebsd-x86_64"
        )
        ;;
        
    *)
        NATIVE_TOOLS_DEPLOYMENT_TARGETS=(
            "mingw-x86_64"
        )
        ;;

    *)
        echo "Unknown operating system"
        exit 1
        ;;
esac

# Sanitize the list of cross-compilation targets.
for t in ${CROSS_COMPILE_TOOLS_DEPLOYMENT_TARGETS} ; do
    case ${t} in
        iphonesimulator-i386 | iphonesimulator-x86_64 | \
        iphoneos-arm64 | iphoneos-armv7 | \
        appletvos-arm64 | appletvsimulator-x86_64 | \
        watchos-armv7k | watchsimulator-i386)
            CROSS_TOOLS_DEPLOYMENT_TARGETS=(
                "${CROSS_TOOLS_DEPLOYMENT_TARGETS[@]}"
                "${t}"
            )
            ;;
        *)
            echo "Unknown deployment target"
            exit 1
            ;;
    esac
done

function is_native_tools_deployment_target() {
    local deployment_target="$1"
    for t in "${NATIVE_TOOLS_DEPLOYMENT_TARGETS[@]}" ; do
        if [ "${deployment_target}" == "${t}" ] ; then
            echo 1
        fi
    done
}

function is_cross_tools_deployment_target() {
    local deployment_target="$1"
    for t in "${CROSS_TOOLS_DEPLOYMENT_TARGETS[@]}" ; do
        if [ "${deployment_target}" == "${t}" ] ; then
            echo 1
        fi
    done
}

# A list of deployment targets that we compile or cross-compile the
# Swift standard library for.
STDLIB_DEPLOYMENT_TARGETS=()

case "$(uname -s)" in
    Linux)
        STDLIB_DEPLOYMENT_TARGETS=(
            "linux-x86_64"
        )
        ;;

    Darwin)
        STDLIB_DEPLOYMENT_TARGETS=(
            "macosx-x86_64"
            "iphonesimulator-i386"
            "iphonesimulator-x86_64"
            "appletvsimulator-x86_64"
            "watchsimulator-i386"

            # Put iOS native targets last so that we test them last (it takes a
            # long time).
            "iphoneos-arm64"
            "iphoneos-armv7"
            "appletvos-arm64"
            "watchos-armv7k"
        )
        ;;

    FreeBSD)
        STDLIB_DEPLOYMENT_TARGETS=(
            "freebsd-x86_64"
        )
        ;;

    *)
        echo "Unknown operating system"
        exit 1
        ;;
esac

#
# Calculate source directories for each product.
#
NINJA_SOURCE_DIR="$WORKSPACE/ninja"
SWIFT_SOURCE_DIR="$WORKSPACE/swift"
LLVM_SOURCE_DIR="$WORKSPACE/llvm"
CMARK_SOURCE_DIR="$WORKSPACE/cmark"
LLDB_SOURCE_DIR="$WORKSPACE/lldb"
LLBUILD_SOURCE_DIR="$WORKSPACE/llbuild"
SWIFTPM_SOURCE_DIR="$WORKSPACE/swiftpm"
XCTEST_SOURCE_DIR="$WORKSPACE/swift-corelibs-xctest"
FOUNDATION_SOURCE_DIR="$WORKSPACE/swift-corelibs-foundation"

if [[ ! -d $CMARK_SOURCE_DIR ]]; then
  echo "$CMARK_SOURCE_DIR not found. Attempting to clone ..."
  git clone https://github.com/apple/swift-cmark.git "$CMARK_SOURCE_DIR" || \
    (echo "Couldn't clone cmark. Please check README.md and visit https://github.com/apple/swift-cmark for details." && \
    exit 1)
fi

if [[ ! "$SKIP_BUILD_LLBUILD" && ! -d $LLBUILD_SOURCE_DIR ]]; then
    echo "Couldn't find llbuild source directory."
    exit 1
fi

if [[ ! "$SKIP_BUILD_SWIFTPM" && ! -d $SWIFTPM_SOURCE_DIR ]]; then
    echo "Couldn't find swiftpm source directory."
    exit 1
fi

if [[ ! "$SKIP_BUILD_XCTEST" && ! -d $XCTEST_SOURCE_DIR ]]; then
    echo "Couldn't find XCTest source directory."
    exit 1
fi

if [[ ! "$SKIP_BUILD_FOUNDATION" && ! -d $FOUNDATION_SOURCE_DIR ]]; then
    echo "Couldn't find Foundation source directory."
    exit 1
fi

# Symlink clang into the llvm tree.
CLANG_SOURCE_DIR="${LLVM_SOURCE_DIR}/tools/clang"
if [ ! -e "${WORKSPACE}/clang" ] ; then
    # If llvm/tools/clang is already a directory, use that and skip the symlink.
    if [ ! -d "${CLANG_SOURCE_DIR}" ] ; then
        echo "Can't find source directory for clang (tried ${WORKSPACE}/clang and ${CLANG_SOURCE_DIR})"
        exit 1
    fi
fi
if [ ! -d "${CLANG_SOURCE_DIR}" ] ; then
    ln -sf "${WORKSPACE}/clang" "${CLANG_SOURCE_DIR}"
fi

PRODUCTS=(cmark llvm swift)
if [[ ! "${SKIP_BUILD_LLDB}" ]] ; then
     PRODUCTS=("${PRODUCTS[@]}" lldb)
fi
if [[ ! "${SKIP_BUILD_LLBUILD}" ]] ; then
     PRODUCTS=("${PRODUCTS[@]}" llbuild)
fi
if [[ ! "${SKIP_BUILD_SWIFTPM}" ]] ; then
     PRODUCTS=("${PRODUCTS[@]}" swiftpm)
fi
if [[ ! "${SKIP_BUILD_XCTEST}" ]] ; then
     PRODUCTS=("${PRODUCTS[@]}" xctest)
fi
if [[ ! "${SKIP_BUILD_FOUNDATION}" ]] ; then
     PRODUCTS=("${PRODUCTS[@]}" foundation)
fi

SWIFT_STDLIB_TARGETS=()
SWIFT_TEST_TARGETS=()
for deployment_target in "${STDLIB_DEPLOYMENT_TARGETS[@]}"; do
    build_for_this_target=1
    test_this_target=1
    case $deployment_target in
        linux-*)
            build_for_this_target=1
            test_this_target=1
            ;;
        freebsd-*)
            build_for_this_target=1
            test_this_target=1
            ;;
        macosx-*)
            build_for_this_target=$(not $SKIP_BUILD_OSX)
            test_this_target=$(not $SKIP_TEST_OSX)
            ;;
        iphoneos-*)
            build_for_this_target=$(not $SKIP_BUILD_IOS_DEVICE)
            test_this_target=
            ;;
        iphonesimulator-*)
            build_for_this_target=$(not $SKIP_BUILD_IOS_SIMULATOR)
            test_this_target=$(not $SKIP_TEST_IOS_SIMULATOR)
            ;;
        appletvos-*)
            build_for_this_target=$(not $SKIP_BUILD_TVOS_DEVICE)
            test_this_target=
            ;;
        appletvsimulator-*)
            build_for_this_target=$(not $SKIP_BUILD_TVOS_SIMULATOR)
            test_this_target=$(not $SKIP_TEST_TVOS_SIMULATOR)
            ;;
        watchos-*)
            build_for_this_target=$(not $SKIP_BUILD_WATCHOS_DEVICE)
            test_this_target=
            ;;
        watchsimulator-*)
            build_for_this_target=$(not $SKIP_BUILD_WATCHOS_SIMULATOR)
            test_this_target=$(not $SKIP_TEST_WATCHOS_SIMULATOR)
            ;;
        *)
            echo "Unknown compiler deployment target: $deployment_target"
            exit 1
            ;;
    esac
    if [[ "$build_for_this_target" ]] ; then
        SWIFT_STDLIB_TARGETS=(
            "${SWIFT_STDLIB_TARGETS[@]}" "swift-stdlib-${deployment_target}")
    fi
    if [[ "$test_this_target" ]] ; then
        if [[ "$SKIP_TEST_VALIDATION" ]] ; then
            SWIFT_TEST_TARGETS=(
                "${SWIFT_TEST_TARGETS[@]}" "check-swift-${deployment_target}")
            if [[ $(not $SKIP_TEST_OPTIMIZED) ]] ; then
              SWIFT_TEST_TARGETS=(
                 "${SWIFT_TEST_TARGETS[@]}" "check-swift-optimize-${deployment_target}")
            fi
        else
            SWIFT_TEST_TARGETS=(
                "${SWIFT_TEST_TARGETS[@]}" "check-swift-all-${deployment_target}")
            if [[ $(not $SKIP_TEST_OPTIMIZED) ]] ; then
              SWIFT_TEST_TARGETS=(
                 "${SWIFT_TEST_TARGETS[@]}" "check-swift-all-optimize-${deployment_target}")
            fi

        fi
    fi
done

echo "Building the standard library for: ${SWIFT_STDLIB_TARGETS[@]}"
echo "Running Swift tests for: ${SWIFT_TEST_TARGETS[@]}"
echo

# CMake options used for all targets, including LLVM/Clang
COMMON_CMAKE_OPTIONS=(
    -G "${CMAKE_GENERATOR}"
)

COMMON_C_FLAGS=""
COMMON_CXX_FLAGS=""

if [[ "${ENABLE_ASAN}" ]] ; then
    COMMON_CMAKE_OPTIONS=(
        "${COMMON_CMAKE_OPTIONS[@]}"
        -DLLVM_USE_SANITIZER="Address"
    )
fi

if [ -z "${HOST_CC}" ] ; then
    if [ "$(uname -s)" == "Darwin" ] ; then
        HOST_CC="$(xcrun_find_tool clang)"
        HOST_CXX="$(xcrun_find_tool clang++)"
    else
        for clang_candidate_suffix in "" "-3.8" "-3.7" "-3.6" "-3.5" ; do
            if which "clang${clang_candidate_suffix}" > /dev/null ; then
                HOST_CC="clang${clang_candidate_suffix}"
                HOST_CXX="clang++${clang_candidate_suffix}"
                break
            fi
        done
    fi
fi
if [ -z "${HOST_CC}" ] ; then
    echo "Can't find clang.  Please install clang-3.5 or a later version."
    exit 1
fi

if [[ "$DISTCC" ]] ; then
    # On some platforms, 'pump' may be unrelated to distcc, in which case it's
    # called 'distcc-pump'.
    DISTCC_PUMP="$(which distcc-pump || which pump)"
    COMMON_CMAKE_OPTIONS=(
        "${COMMON_CMAKE_OPTIONS[@]}"
        -DCMAKE_C_COMPILER:PATH="$(which distcc)"
        -DCMAKE_C_COMPILER_ARG1="${HOST_CC}"
        -DCMAKE_CXX_COMPILER:PATH="$(which distcc)"
        -DCMAKE_CXX_COMPILER_ARG1="${HOST_CXX}"
    )
else
    COMMON_CMAKE_OPTIONS=(
        "${COMMON_CMAKE_OPTIONS[@]}"
        -DCMAKE_C_COMPILER:PATH="${HOST_CC}"
        -DCMAKE_CXX_COMPILER:PATH="${HOST_CXX}"
    )
fi

if [[ "$DISTCC" ]] ; then
    BUILD_ARGS="${BUILD_ARGS} -j $(distcc -j)"
fi

case "${CMAKE_GENERATOR}" in
    Ninja)
        if [[ "${VERBOSE_BUILD}" ]] ; then
            BUILD_ARGS="${BUILD_ARGS} -v"
        fi
        if [[ "${BUILD_JOBS}" ]] ; then
            BUILD_ARGS="${BUILD_ARGS} -j${BUILD_JOBS}"
        fi
        ;;
    'Unix Makefiles')
        if [[ "${BUILD_JOBS}" ]] ; then
            BUILD_ARGS="${BUILD_ARGS} -j${BUILD_JOBS}"
        else
            BUILD_ARGS="${BUILD_ARGS:--j$(get_make_parallelism)}"
        fi
        if [[ "${VERBOSE_BUILD}" ]] ; then
            BUILD_ARGS="${BUILD_ARGS} VERBOSE=1"
        fi
        ;;
    Xcode)
        # -parallelizeTargets is an unsupported flag from the Xcode 3 days,
        # but since we're not using proper Xcode 4 schemes, this is the
        # only way to get target-level parallelism.
        BUILD_ARGS="${BUILD_ARGS} -parallelizeTargets"
        if [[ "${BUILD_JOBS}" ]] ; then
            BUILD_ARGS="${BUILD_ARGS} -jobs ${BUILD_JOBS}"
        fi
        BUILD_TARGET_FLAG="-target"
        COMMON_CMAKE_OPTIONS=(
            "${COMMON_CMAKE_OPTIONS[@]}"
            -DCMAKE_CONFIGURATION_TYPES="Debug;Release;MinSizeRel;RelWithDebInfo"
        )
        if [[ "${XCODE_IDE_ONLY}" ]]; then
          COMMON_CMAKE_OPTIONS=(
              "${COMMON_CMAKE_OPTIONS[@]}"
              -DSWIFT_XCODE_GENERATE_FOR_IDE_ONLY=ON
          )
        fi
        ;;
esac

if [[ "${CLANG_COMPILER_VERSION}" ]] ; then
    major_version=$(echo "${CLANG_COMPILER_VERSION}" | sed -e 's/\([0-9]*\).*/\1/')
    minor_version=$(echo "${CLANG_COMPILER_VERSION}" | sed -e 's/[^.]*\.\([0-9]*\).*/\1/')
    patch_version=$(echo "${CLANG_COMPILER_VERSION}" | sed -e 's/[^.]*\.[^.]*\.\([0-9]*\)/\1/')
    COMMON_CMAKE_OPTIONS=(
        "${COMMON_CMAKE_OPTIONS[@]}"
        -DLLVM_VERSION_MAJOR:STRING="${major_version}"
        -DLLVM_VERSION_MINOR:STRING="${minor_version}"
        -DLLVM_VERSION_PATCH:STRING="${patch_version}"
    )
fi

#
# Record SDK and tools versions for posterity
#
if [[ "$SHOW_SDKS" ]] ; then
    echo "--- SDK versions ---"
    xcodebuild -version || :
    echo
    if [[ ! "$SKIP_IOS" ]] ; then
        xcodebuild -version -sdk iphonesimulator || :
    fi
    if [[ ! "$SKIP_TVOS" ]] ; then
        xcodebuild -version -sdk appletvsimulator || :
    fi
    if [[ ! "$SKIP_WATCHOS" ]] ; then
        xcodebuild -version -sdk watchsimulator || :
    fi
fi

function build_directory() {
    deployment_target=$1
    product=$2
    echo "$BUILD_DIR/$product-$deployment_target"
}

function build_directory_bin() {
    deployment_target=$1
    product=$2
    root="$(build_directory $deployment_target $product)"
    if [[ "${CMAKE_GENERATOR}" == "Xcode" ]] ; then
        case $product in
            cmark)
                echo "${root}/${CMARK_BUILD_TYPE}/bin"
                ;;
            llvm)
                echo "${root}/${LLVM_BUILD_TYPE}/bin"
                ;;
            swift)
                echo "${root}/${SWIFT_BUILD_TYPE}/bin"
                ;;
            lldb)
                ;;
            llbuild)
                echo "${root}/${LLBUILD_BUILD_TYPE}/bin"
                ;;
            swiftpm)
                echo "${root}/${SWIFTPM_BUILD_TYPE}/bin"
                ;;
            xctest)
                echo "${root}/${XCTEST_BUILD_TYPE}/bin"
                ;;
            foundation)
                echo "${root}/${FOUNDATION_BUILD_TYPE}/bin"
                ;;
            *)
                echo "error: unknown product: ${product}"
                exit 1
                ;;
        esac
    else
        echo "${root}/bin"
    fi
}

function is_cmake_release_build_type() {
    if [[ "$1" == "Release" || "$1" == "RelWithDebInfo" ]] ; then
        echo 1
    fi
}

function common_cross_c_flags() {
    echo -n "${COMMON_C_FLAGS}"

    case $1 in
        iphonesimulator-i386)
            echo "-arch i386 -mios-simulator-version-min=${DARWIN_DEPLOYMENT_VERSION_IOS}"
            ;;
        iphonesimulator-x86_64)
            echo "-arch x86_64 -mios-simulator-version-min=${DARWIN_DEPLOYMENT_VERSION_IOS}"
            ;;
        iphoneos-armv7)
            echo "-arch armv7 -miphoneos-version-min=${DARWIN_DEPLOYMENT_VERSION_IOS}"
            ;;
        iphoneos-arm64)
            echo "-arch arm64 -miphoneos-version-min=${DARWIN_DEPLOYMENT_VERSION_IOS}"
            ;;
        appletvsimulator-x86_64)
            echo "-arch x86_64 -mtvos-simulator-version-min=${DARWIN_DEPLOYMENT_VERSION_TVOS}"
            ;;
        appletvos-arm64)
            echo "-arch arm64 -mtvos-version-min=${DARWIN_DEPLOYMENT_VERSION_TVOS}"
            ;;
        watchsimulator-i386)
            echo "-arch i386 -mwatchos-simulator-version-min=${DARWIN_DEPLOYMENT_VERSION_WATCHOS}"
            ;;
        watchos-armv7k)
            echo "-arch armv7k -mwatchos-version-min=${DARWIN_DEPLOYMENT_VERSION_WATCHOS}"
            ;;
    esac
}

function llvm_c_flags() {
    echo -n " $(common_cross_c_flags $1)"
    if [[ $(is_cmake_release_build_type "${LLVM_BUILD_TYPE}") ]] ; then
        echo -n " -fno-stack-protector"
    fi
}

function cmark_c_flags() {
    echo -n " $(common_cross_c_flags $1)"
    if [[ $(is_cmake_release_build_type "${LLVM_BUILD_TYPE}") ]] ; then
        echo -n " -fno-stack-protector"
    fi
}

function swift_c_flags() {
    # Don’t pass common_cross_c_flags to Swift because CMake code in the Swift
    # project is itself aware of cross-compilation for the host tools and
    # standard library.
    echo -n "${COMMON_C_FLAGS}"
    if [[ $(is_cmake_release_build_type "${SWIFT_BUILD_TYPE}") ]] ; then
        echo -n " -fno-stack-protector"
    fi
}

function cmake_config_opt() {
    product=$1
    if [[ "${CMAKE_GENERATOR}" == "Xcode" ]] ; then
        # CMake automatically adds --target ALL_BUILD if we don't pass this.
        echo "--target ZERO_CHECK "
        case $product in
            cmark)
                echo "--config ${CMARK_BUILD_TYPE}"
                ;;
            llvm)
                echo "--config ${LLVM_BUILD_TYPE}"
                ;;
            swift)
                echo "--config ${SWIFT_BUILD_TYPE}"
                ;;
            lldb)
                ;;
            llbuild)
                echo "--config ${LLBUILD_BUILD_TYPE}"
                ;;
            swiftpm)
                echo "--config ${SWIFTPM_BUILD_TYPE}"
                ;;
            xctest)
                echo "--config ${XCTEST_BUILD_TYPE}"
                ;;
            foundation)
                echo "--config ${FOUNDATION_BUILD_TYPE}"
                ;;            
            *)
                echo "error: unknown product: ${product}"
                exit 1
                ;;
        esac
    fi
}

function should_build_perftestsuite() {
    if [ "$(uname -s)" != Darwin ]; then
        echo "FALSE"
        return
    fi

    echo $(true_false "${BUILD_SWIFT_PERF_TESTSUITE}")
}

function set_swiftpm_bootstrap_command() {
    swiftpm_bootstrap_command=()
    
    SWIFTC_BIN="$(build_directory_bin $deployment_target swift)/swiftc"
    LLBUILD_BIN="$(build_directory_bin $deployment_target llbuild)/swift-build-tool"
    if [[ ! "${SKIP_BUILD_XCTEST}" ]] ; then
        XCTEST_BUILD_DIR=$(build_directory $deployment_target xctest)
    fi
    if [ ! -e "${LLBUILD_BIN}" ]; then
        echo "Error: Cannot build swiftpm without llbuild (swift-build-tool)."
        exit 1
    fi
    swiftpm_bootstrap_command=("${SWIFTPM_SOURCE_DIR}/Utilities/bootstrap" "${swiftpm_bootstrap_options[@]}")
    if [[ "${VERBOSE_BUILD}" ]] ; then
        swiftpm_bootstrap_command=("${swiftpm_bootstrap_command[@]}" -v)
    fi
    swiftpm_bootstrap_command=("${swiftpm_bootstrap_command[@]}" --swiftc="${SWIFTC_BIN}")
    swiftpm_bootstrap_command=("${swiftpm_bootstrap_command[@]}" --sbt="${LLBUILD_BIN}")
    swiftpm_bootstrap_command=("${swiftpm_bootstrap_command[@]}" --build="${build_dir}")
    if [[ ! "${SKIP_BUILD_XCTEST}" ]] ; then
        swiftpm_bootstrap_command=("${swiftpm_bootstrap_command[@]}" --xctest="${XCTEST_BUILD_DIR}")
    fi
}

mkdir -p "${BUILD_DIR}"

#
# Build Ninja
#
if [[ "${BUILD_NINJA}" ]] ; then
    build_dir=$(build_directory build ninja)
    if [ ! -f "${build_dir}/ninja" ] ; then
        if [ ! -d "${NINJA_SOURCE_DIR}" ] ; then
          echo "Can't find source directory for ninja (tried ${NINJA_SOURCE_DIR})"
          exit 1
        fi

        # Ninja can only be built in-tree.  Copy the source tree to the build
        # directory.
        set -x
        rm -rf "${build_dir}"
        cp -r "${NINJA_SOURCE_DIR}" "${build_dir}"
        if [[ $(uname -s) == "Darwin" ]]; then
          (cd "${build_dir}" && \
            env CXX=$(xcrun --sdk macosx -find clang++) \
                CFLAGS="-isysroot $(xcrun --sdk macosx --show-sdk-path) -mmacosx-version-min=${DARWIN_DEPLOYMENT_VERSION_OSX}" \
                LDFLAGS="-mmacosx-version-min=${DARWIN_DEPLOYMENT_VERSION_OSX}" \
                python ./configure.py --bootstrap)
          { set +x; } 2>/dev/null
        else
          (cd "${build_dir}" && python ./configure.py --bootstrap)
          { set +x; } 2>/dev/null
        fi
    fi
    export PATH="${build_dir}:${PATH}"
fi

#
# Configure and build each product
#
# Start with native deployment targets because the resulting tools are used during cross-compilation.
for deployment_target in "${NATIVE_TOOLS_DEPLOYMENT_TARGETS[@]}" "${CROSS_TOOLS_DEPLOYMENT_TARGETS[@]}"; do
    set_deployment_target_based_options

    case "${COMPILER_VENDOR}" in
        none)
            ;;
        apple)
            # User-visible versions of the compiler.
            CLANG_USER_VISIBLE_VERSION="6.1.0"
            SWIFT_USER_VISIBLE_VERSION="2.2"

            llvm_cmake_options=(
                "${llvm_cmake_options[@]}"
                -DCLANG_VENDOR=Apple
                -DCLANG_VENDOR_UTI=com.apple.compilers.llvm.clang
                -DPACKAGE_VERSION="${CLANG_USER_VISIBLE_VERSION}"
            )
            swift_cmake_options=(
                "${swift_cmake_options[@]}"
                -DSWIFT_VENDOR=Apple
                -DSWIFT_VENDOR_UTI=com.apple.compilers.llvm.swift
                -DSWIFT_VERSION="${SWIFT_USER_VISIBLE_VERSION}"
                -DSWIFT_COMPILER_VERSION="${SWIFT_COMPILER_VERSION}"
            )
            ;;
        *)
            echo "unknown compiler vendor"
            exit 1
            ;;
    esac

    llvm_cmake_options=(
        "${llvm_cmake_options[@]}"
        -DCMAKE_INSTALL_PREFIX:PATH="${INSTALL_PREFIX}"
        -DINTERNAL_INSTALL_PREFIX="local"
    )

    if [[ "${CLANG_COMPILER_VERSION}" ]] ; then
        llvm_cmake_options=(
            "${llvm_cmake_options[@]}"
            -DCLANG_REPOSITORY_STRING="clang-${CLANG_COMPILER_VERSION}"
        )
        swift_cmake_options=(
            "${swift_cmake_options[@]}"
            -DCLANG_COMPILER_VERSION="${CLANG_COMPILER_VERSION}"
            -DSWIFT_COMPILER_VERSION="${SWIFT_COMPILER_VERSION}"
        )
    fi
    if [[ "${SWIFT_COMPILER_VERSION}" ]] ; then
        swift_cmake_options=(
            "${swift_cmake_options[@]}"
            -DSWIFT_COMPILER_VERSION="${SWIFT_COMPILER_VERSION}"
        )
    fi

    if [[ "${ENABLE_ASAN}" ]] ; then
        swift_cmake_options=(
            "${swift_cmake_options[@]}"
            -DSWIFT_SOURCEKIT_USE_INPROC_LIBRARY:BOOL=TRUE
        )
    fi

    if [[ "${DARWIN_CRASH_REPORTER_CLIENT}" ]] ; then
        swift_cmake_options=(
            "${swift_cmake_options[@]}"
            -DSWIFT_RUNTIME_CRASH_REPORTER_CLIENT:BOOL=TRUE
        )
    fi

    if [[ "${DARWIN_STDLIB_INSTALL_NAME_DIR}" ]] ; then
        swift_cmake_options=(
            "${swift_cmake_options[@]}"
            -DSWIFT_DARWIN_STDLIB_INSTALL_NAME_DIR:STRING="${DARWIN_STDLIB_INSTALL_NAME_DIR}"
        )
    fi

    if [[ "${EXTRA_SWIFT_ARGS}" ]] ; then
        swift_cmake_options=(
            "${swift_cmake_options[@]}"
            -DSWIFT_EXPERIMENTAL_EXTRA_REGEXP_FLAGS="${EXTRA_SWIFT_ARGS}"
        )
    fi

    if [[ $(should_build_perftestsuite) == "TRUE" ]]; then
        swift_cmake_options=(
            "${swift_cmake_options[@]}"
            -DSWIFT_INCLUDE_PERF_TESTSUITE=YES
        )
    fi

    swift_cmake_options=(
        "${swift_cmake_options[@]}"
        -DSWIFT_AST_VERIFIER:BOOL=$(true_false "${SWIFT_ENABLE_AST_VERIFIER}")
        -DSWIFT_VERIFY_ALL:BOOL=$(true_false "${SIL_VERIFY_ALL}")
        -DSWIFT_RUNTIME_ENABLE_DTRACE:BOOL=$(true_false "${SWIFT_RUNTIME_ENABLE_DTRACE}")
        -DSWIFT_RUNTIME_ENABLE_LEAK_CHECKER:BOOL=$(true_false "${SWIFT_RUNTIME_ENABLE_LEAK_CHECKER}")
    )

    for product in "${PRODUCTS[@]}"; do
        unset skip_build
        build_dir=$(build_directory $deployment_target $product)
        build_targets=(all)
        cmake_options=("${COMMON_CMAKE_OPTIONS[@]}")

        # Add in gold linker support if requested.
        if [[ "$USE_GOLD_LINKER" ]]; then
            echo "${product}: using gold linker"
            if [[ "${product}" != "swift" ]]; then
                # All other projects override the linker flags to add in
                # gold linker support.
                cmake_options=(
                    "${cmake_options[@]}"
                    -DCMAKE_EXE_LINKER_FLAGS:STRING="-fuse-ld=gold"
                    -DCMAKE_SHARED_LINKER_FLAGS:STRING="-fuse-ld=gold"
                )
            fi
        else
            echo "${product}: using standard linker"
        fi

        PRODUCT=$(toupper $product)
        llvm_build_dir=$(build_directory $deployment_target llvm)
        module_cache="${build_dir}/module-cache"
        swift_cmake_options=(
            "${swift_cmake_options[@]}"
            -DCMAKE_INSTALL_PREFIX:PATH="${INSTALL_PREFIX}"
            -DLLVM_CONFIG:PATH="$(build_directory_bin $deployment_target llvm)/llvm-config"
            -D${PRODUCT}_PATH_TO_CLANG_SOURCE:PATH="${CLANG_SOURCE_DIR}"
            -D${PRODUCT}_PATH_TO_CLANG_BUILD:PATH="${llvm_build_dir}"
            -D${PRODUCT}_PATH_TO_LLVM_SOURCE:PATH="${LLVM_SOURCE_DIR}"
            -D${PRODUCT}_PATH_TO_LLVM_BUILD:PATH="${llvm_build_dir}"
            -D${PRODUCT}_PATH_TO_CMARK_SOURCE:PATH="${CMARK_SOURCE_DIR}"
            -D${PRODUCT}_PATH_TO_CMARK_BUILD:PATH="$(build_directory $deployment_target cmark)"
        )

        if [[ "${CMAKE_GENERATOR}" == "Xcode" ]] ; then
            swift_cmake_options=(
                "${swift_cmake_options[@]-}"
                -D${PRODUCT}_CMARK_LIBRARY_DIR:PATH=$(build_directory $deployment_target cmark)/src/$CMARK_BUILD_TYPE
            )
        else
            swift_cmake_options=(
                "${swift_cmake_options[@]-}"
                -D${PRODUCT}_CMARK_LIBRARY_DIR:PATH=$(build_directory $deployment_target cmark)/src
            )
        fi

        case $product in
            cmark)
                cmake_options=(
                  "${cmake_options[@]}"
                  -DCMAKE_BUILD_TYPE:STRING="${LLVM_BUILD_TYPE}"
                  "${cmark_cmake_options[@]}"
                  "${CMARK_SOURCE_DIR}"
                )
                skip_build=$SKIP_BUILD_CMARK
                build_targets=(all)

                ;;

            llvm)
                if [ "${BUILD_LLVM}" == "0" ] ; then
                    build_targets=(clean)
                fi
                if [ "${SKIP_BUILD_LLVM}" ] ; then
                    # We can't skip the build completely because the standalone
                    # build of Swift depend on these.
                    build_targets=(llvm-config llvm-tblgen clang-headers)
                fi

                # Note: we set the variable:
                #
                # LLVM_TOOL_SWIFT_BUILD
                #
                # below because this script builds swift separately, and people
                # often have reasons to symlink the swift directory into
                # llvm/tools, e.g. to build LLDB.
                cmake_options=(
                    "${cmake_options[@]}"
                    -DCMAKE_C_FLAGS="$(llvm_c_flags $deployment_target)"
                    -DCMAKE_CXX_FLAGS="$(llvm_c_flags $deployment_target)"
                    -DCMAKE_BUILD_TYPE:STRING="${LLVM_BUILD_TYPE}"
                    -DLLVM_ENABLE_ASSERTIONS:BOOL=$(true_false "${LLVM_ENABLE_ASSERTIONS}")
                    -DLLVM_TOOL_SWIFT_BUILD:BOOL=NO
                    -DLLVM_TARGETS_TO_BUILD="${LLVM_TARGETS_TO_BUILD}"
                    -DLLVM_INCLUDE_TESTS:BOOL=$(true_false "${SOURCE_TREE_INCLUDES_TESTS}")
                    -LLVM_INCLUDE_DOCS:BOOL=TRUE
                    "${llvm_cmake_options[@]}"
                    "${LLVM_SOURCE_DIR}"
                )
                if [[ $(is_cross_tools_deployment_target $deployment_target) ]] ; then
                    # FIXME: don't hardcode macosx-x86_64.
                    cmake_options=(
                        "${cmake_options[@]}"
                        -DLLVM_TABLEGEN=$(build_directory macosx-x86_64 llvm)/bin/llvm-tblgen
                        -DCLANG_TABLEGEN=$(build_directory macosx-x86_64 llvm)/bin/clang-tblgen
                    )
                fi

                ;;

            swift)
                cmake_options=("${COMMON_CMAKE_OPTIONS[@]}")
                if [[ "$USE_GOLD_LINKER" ]]; then
                    # Swift will selectively use the gold linker on all
                    # parts except building the standard library.  We
                    # let the Swift cmake setup figure out how to apply
                    # that.
                    cmake_options=(
                        "${cmake_options[@]}"
                        -DSWIFT_ENABLE_GOLD_LINKER=TRUE
                    )
                fi

                native_llvm_tools_path=""
                native_clang_tools_path=""
                native_swift_tools_path=""
                if [[ $(is_cross_tools_deployment_target $deployment_target) ]] ; then
                    build_tests_this_time=false

                    # FIXME: don't hardcode macosx-x86_64.
                    native_llvm_tools_path="$(build_directory macosx-x86_64 llvm)/bin"
                    native_clang_tools_path="$(build_directory macosx-x86_64 llvm)/bin"
                    native_swift_tools_path="$(build_directory macosx-x86_64 swift)/bin"

                    cmake_options=(
                        "${cmake_options[@]}"
                        -DLLVM_TOOLS_BINARY_DIR:PATH=$(build_directory $deployment_target llvm)/bin
                        -DLLVM_LIBRARY_DIR:PATH=$(build_directory $deployment_target llvm)/lib
                        -DLLVM_MAIN_INCLUDE_DIR:PATH=$(build_directory $deployment_target llvm)/include
                        -DLLVM_BINARY_DIR:PATH=$(build_directory $deployment_target llvm)
                        -DLLVM_MAIN_SRC_DIR:PATH="${LLVM_SOURCE_DIR}"
                    )
                else
                    build_tests_this_time=${SOURCE_TREE_INCLUDES_TESTS}
                fi

                # Command-line parameters override any autodetection that we
                # might have done.
                if [[ "${NATIVE_LLVM_TOOLS_PATH}" ]] ; then
                    native_llvm_tools_path="${NATIVE_LLVM_TOOLS_PATH}"
                fi
                if [[ "${NATIVE_CLANG_TOOLS_PATH}" ]] ; then
                    native_clang_tools_path="${NATIVE_CLANG_TOOLS_PATH}"
                fi
                if [[ "${NATIVE_SWIFT_TOOLS_PATH}" ]] ; then
                    native_swift_tools_path="${NATIVE_SWIFT_TOOLS_PATH}"
                fi

                if [ "${BUILD_LLVM}" == "0" ] ; then
                    cmake_options=(
                        "${cmake_options[@]}"
                        -DLLVM_TOOLS_BINARY_DIR:PATH=/tmp/dummy
                        -DLLVM_LIBRARY_DIR:PATH="${build_dir}"
                        -DLLVM_MAIN_INCLUDE_DIR:PATH=/tmp/dummy
                        -DLLVM_BINARY_DIR:PATH=$(build_directory $deployment_target llvm)
                        -DLLVM_MAIN_SRC_DIR:PATH="${LLVM_SOURCE_DIR}"
                    )
                fi

                cmake_options=(
                    "${cmake_options[@]}"
                    -DCMAKE_C_FLAGS="$(swift_c_flags $deployment_target)"
                    -DCMAKE_CXX_FLAGS="$(swift_c_flags $deployment_target)"
                    -DCMAKE_BUILD_TYPE:STRING="${SWIFT_BUILD_TYPE}"
                    -DLLVM_ENABLE_ASSERTIONS:BOOL=$(true_false "${SWIFT_ENABLE_ASSERTIONS}")
                    -DSWIFT_STDLIB_BUILD_TYPE:STRING="${SWIFT_STDLIB_BUILD_TYPE}"
                    -DSWIFT_STDLIB_ASSERTIONS:BOOL=$(true_false "${SWIFT_STDLIB_ENABLE_ASSERTIONS}")
                    -DSWIFT_NATIVE_LLVM_TOOLS_PATH:STRING="${native_llvm_tools_path}"
                    -DSWIFT_NATIVE_CLANG_TOOLS_PATH:STRING="${native_clang_tools_path}"
                    -DSWIFT_NATIVE_SWIFT_TOOLS_PATH:STRING="${native_swift_tools_path}"
                    -DSWIFT_BUILD_TOOLS:BOOL=$(true_false "${BUILD_SWIFT_TOOLS}")
                    -DSWIFT_BUILD_STDLIB:BOOL=$(true_false "${BUILD_SWIFT_STDLIB}")
                    -DSWIFT_BUILD_SDK_OVERLAY:BOOL=$(true_false "${BUILD_SWIFT_SDK_OVERLAY}")
                    -DSWIFT_BUILD_STATIC_STDLIB:BOOL=$(true_false "${BUILD_SWIFT_STATIC_STDLIB}")
                    -DSWIFT_BUILD_EXAMPLES:BOOL=$(true_false "${BUILD_SWIFT_EXAMPLES}")
                    -DSWIFT_INCLUDE_TESTS:BOOL=$(true_false "${build_tests_this_time}")
                    -DSWIFT_INSTALL_COMPONENTS:STRING="${SWIFT_INSTALL_COMPONENTS}"
                    -DSWIFT_EMBED_BITCODE_SECTION:BOOL=$(true_false "${EMBED_BITCODE_SECTION}")
                    "${swift_cmake_options[@]}"
                    "${SWIFT_SOURCE_DIR}"
                )
                if [[ "${SWIFT_SDKS}" ]] ; then
                    cmake_options=(
                        "${cmake_options[@]}"
                        -DSWIFT_SDKS:STRING="${SWIFT_SDKS}"
                    )
                fi
                if [[ "${SWIFT_PRIMARY_VARIANT_SDK}" ]] ; then
                    cmake_options=(
                        "${cmake_options[@]}"
                        -DSWIFT_PRIMARY_VARIANT_SDK:STRING="${SWIFT_PRIMARY_VARIANT_SDK}"
                        -DSWIFT_PRIMARY_VARIANT_ARCH:STRING="${SWIFT_PRIMARY_VARIANT_ARCH}"
                    )
                fi

                build_targets=(all "${SWIFT_STDLIB_TARGETS[@]}")
                if [[ $(should_build_perftestsuite) == "TRUE" ]]; then
                    build_targets=("${build_targets[@]}" benchmark-swift)
                fi
                skip_build=$SKIP_BUILD_SWIFT
                ;;

            lldb)
                if [ ! -d "$LLDB_SOURCE_DIR" ]; then
                    echo "error: lldb not found in ${LLDB_SOURCE_DIR}"
                    exit 1
                fi
                if [[ "${CMAKE_GENERATOR}" != "Ninja" ]] ; then
                    echo "error: lldb can only build with ninja"
                    exit 1
                fi
                cmark_build_dir=$(build_directory $deployment_target cmark)
                lldb_build_dir=$(build_directory $deployment_target lldb)
                swift_build_dir=$(build_directory $deployment_target swift)

                # Add any lldb extra cmake arguments here.
                if [ ! -z "$LLDB_EXTRA_CMAKE_ARGS" ]; then
                    cmake_options=(
                        "${cmake_options[@]}"
                        $LLDB_EXTRA_CMAKE_ARGS
                        )
                fi

                # Figure out if we think this is a buildbot build.
                # This will influence the lldb version line.
                if [ ! -z "$JENKINS_HOME" -a ! -z "$JOB_NAME" -a ! -z "$BUILD_NUMBER" ]; then
                    LLDB_IS_BUILDBOT_BUILD=1
                else
                    LLDB_IS_BUILDBOT_BUILD=0
                fi

                # Get the build date
                LLDB_BUILD_DATE=`date +%Y-%m-%d`

                case "$(uname -s)" in
                    Linux)
                        cmake_options=(
                            "${cmake_options[@]}"
                            -DCMAKE_BUILD_TYPE:STRING="${LLDB_BUILD_TYPE}"
                            -DCMAKE_INSTALL_PREFIX:PATH="${INSTALL_PREFIX}"
                            -DLLDB_PATH_TO_LLVM_SOURCE:PATH="${LLVM_SOURCE_DIR}"
                            -DLLDB_PATH_TO_CLANG_SOURCE:PATH="${CLANG_SOURCE_DIR}"
                            -DLLDB_PATH_TO_SWIFT_SOURCE:PATH="${SWIFT_SOURCE_DIR}"
                            -DLLDB_PATH_TO_LLVM_BUILD:PATH="${llvm_build_dir}"
                            -DLLDB_PATH_TO_CLANG_BUILD:PATH="${llvm_build_dir}"
                            -DLLDB_PATH_TO_SWIFT_BUILD:PATH="${swift_build_dir}"
                            -DLLDB_PATH_TO_CMARK_BUILD:PATH="${cmark_build_dir}"
                            -DLLDB_IS_BUILDBOT_BUILD="${LLDB_IS_BUILDBOT_BUILD}"
                            -DLLDB_BUILD_DATE:STRING="\"${LLDB_BUILD_DATE}\""
                            -DLLDB_ALLOW_STATIC_BINDINGS=1
                            "${LLDB_SOURCE_DIR}"
                        )
                        ;;
                    FreeBSD)
                        cmake_options=(
                            "${cmake_options[@]}"
                            -DCMAKE_BUILD_TYPE:STRING="${LLDB_BUILD_TYPE}"
                            -DCMAKE_INSTALL_PREFIX:PATH="${INSTALL_PREFIX}"
                            -DLLDB_PATH_TO_LLVM_SOURCE:PATH="${LLVM_SOURCE_DIR}"
                            -DLLDB_PATH_TO_CLANG_SOURCE:PATH="${CLANG_SOURCE_DIR}"
                            -DLLDB_PATH_TO_SWIFT_SOURCE:PATH="${SWIFT_SOURCE_DIR}"
                            -DLLDB_PATH_TO_LLVM_BUILD:PATH="${llvm_build_dir}"
                            -DLLDB_PATH_TO_CLANG_BUILD:PATH="${llvm_build_dir}"
                            -DLLDB_PATH_TO_SWIFT_BUILD:PATH="${swift_build_dir}"
                            -DLLDB_PATH_TO_CMARK_BUILD:PATH="${cmark_build_dir}"
                            -DLLDB_IS_BUILDBOT_BUILD="${LLDB_IS_BUILDBOT_BUILD}"
                            -DLLDB_BUILD_DATE:STRING="\"${LLDB_BUILD_DATE}\""
                            -DLLDB_ALLOW_STATIC_BINDINGS=1
                            "${LLDB_SOURCE_DIR}"
                        )
                        ;;
                    Darwin)
                        # Set up flags to pass to xcodebuild
                        lldb_xcodebuild_options=(
                            LLDB_PATH_TO_LLVM_SOURCE="${LLVM_SOURCE_DIR}"
                            LLDB_PATH_TO_CLANG_SOURCE="${CLANG_SOURCE_DIR}"
                            LLDB_PATH_TO_SWIFT_SOURCE="${SWIFT_SOURCE_DIR}"
                            LLDB_PATH_TO_LLVM_BUILD="${llvm_build_dir}"
                            LLDB_PATH_TO_CLANG_BUILD="${llvm_build_dir}"
                            LLDB_PATH_TO_SWIFT_BUILD="${swift_build_dir}"
                            LLDB_PATH_TO_CMARK_BUILD="${cmark_build_dir}"
                            LLDB_IS_BUILDBOT_BUILD="${LLDB_IS_BUILDBOT_BUILD}"
                            LLDB_BUILD_DATE="\"${LLDB_BUILD_DATE}\""
                            SYMROOT="${lldb_build_dir}"
                            OBJROOT="${lldb_build_dir}"
                        )
                        if [[ "${LLDB_NO_DEBUGSERVER}" ]] ; then
                            lldb_xcodebuild_options=(
                                "${lldb_xcodebuild_options[@]}"
                                DEBUGSERVER_DISABLE_CODESIGN="1"
                                DEBUGSERVER_DELETE_AFTER_BUILD="1"
                            )
                        fi
                        if [[ "${LLDB_USE_SYSTEM_DEBUGSERVER}" ]] ; then
                            lldb_xcodebuild_options=(
                                "${lldb_xcodebuild_options[@]}"
                                DEBUGSERVER_USE_FROM_SYSTEM="1"
                            )
                        fi
                        set_lldb_build_mode
                        pushd ${LLDB_SOURCE_DIR}
                        xcodebuild -target desktop -configuration ${LLDB_BUILD_MODE} ${lldb_xcodebuild_options[@]}
                        popd
                        continue
                        ;;
                esac
                ;;
            llbuild)
                cmake_options=(
                    "${cmake_options[@]}"
                    -DCMAKE_INSTALL_PREFIX:PATH="${INSTALL_PREFIX}"
                    -DLIT_EXECUTABLE:PATH="${LLVM_SOURCE_DIR}/utils/lit/lit.py"
                    -DFILECHECK_EXECUTABLE:PATH="$(build_directory_bin $deployment_target llvm)/FileCheck"
                    -DCMAKE_BUILD_TYPE:STRING="${LLBUILD_BUILD_TYPE}"
                    -DLLVM_ENABLE_ASSERTIONS:BOOL=$(true_false "${LLBUILD_ENABLE_ASSERTIONS}")
                    "${LLBUILD_SOURCE_DIR}"
                )
                ;;
            swiftpm)
                set_swiftpm_bootstrap_command
                set -x
                "${swiftpm_bootstrap_command[@]}"
                { set +x; } 2>/dev/null
                
                # swiftpm installs itself with a bootstrap method. No further cmake building is performed.
                continue
                ;;
            xctest)
                SWIFTC_BIN="$(build_directory_bin $deployment_target swift)/swiftc"
                SWIFT_BUILD_PATH="$(build_directory $deployment_target swift)"
                set -x
                "$XCTEST_SOURCE_DIR"/build_script.py --swiftc="${SWIFTC_BIN}" --build-dir="${build_dir}" --swift-build-dir="${SWIFT_BUILD_PATH}"
                { set +x; } 2>/dev/null

                # XCTest builds itself and doesn't rely on cmake
                continue
                ;;
            foundation)
                # the configuration script requires knowing about XCTest's location for building and running the tests
                XCTEST_BUILD_DIR=$(build_directory $deployment_target xctest)
                SWIFTC_BIN="$(build_directory_bin $deployment_target swift)/swiftc"
                SWIFT_BIN="$(build_directory_bin $deployment_target swift)/swift"
                SWIFT_BUILD_PATH="$(build_directory $deployment_target swift)"
                LLVM_BIN="$(build_directory_bin $deployment_target llvm)"
                NINJA_BIN="ninja"

                if [[ "${BUILD_NINJA}" ]]; then
                    NINJA_BUILD_DIR=$(build_directory build ninja)
                    NINJA_BIN="${NINJA_BUILD_DIR}/ninja"
                fi
                
                set -x
                pushd "${FOUNDATION_SOURCE_DIR}"
                SWIFTC="${SWIFTC_BIN}" CLANG="${LLVM_BIN}"/clang SWIFT="${SWIFT_BIN}" \
                      SDKROOT="${SWIFT_BUILD_PATH}" BUILD_DIR="${build_dir}" DSTROOT="${INSTALL_DESTDIR}" PREFIX="${INSTALL_PREFIX}" ./configure "${FOUNDATION_BUILD_TYPE}" -DXCTEST_BUILD_DIR=${XCTEST_BUILD_DIR}
                $NINJA_BIN
                popd
                { set +x; } 2>/dev/null

                # Foundation builds itself and doesn't use cmake
                continue
                ;;
            *)
                echo "error: unknown product: ${product}"
                exit 1
                ;;
        esac

        # Clean the product-local module cache.
        rm -rf "${module_cache}"
        mkdir -p "${module_cache}"

        # Compute the generator output file to check for, to determine if we
        # must reconfigure. We only handle Ninja for now.
        #
        # This is important for ensuring that if a CMake configuration fails in
        # CI, that we will still be willing to rerun the configuration process.
        generator_output_path=""
        if [[ "${CMAKE_GENERATOR}" == "Ninja" ]] ; then
            generator_output_path="${build_dir}/build.ninja"
        fi

        # Configure if necessary.
        if [[  "${RECONFIGURE}" || ! -f "${build_dir}/CMakeCache.txt" || \
                    ( ! -z "${generator_output_path}" && ! -f "${generator_output_path}" ) ]] ; then
            mkdir -p "${build_dir}"
            set -x
            (cd "${build_dir}" && "$CMAKE" "${cmake_options[@]}" ${USER_CONFIG_ARGS})
            { set +x; } 2>/dev/null
        fi

        # Build.
        if [[ ! "${skip_build}" ]]; then
            if [[ "${CMAKE_GENERATOR}" == "Xcode" ]] ; then
                # Xcode generator uses "ALL_BUILD" instead of "all".
                # Also, xcodebuild uses -target instead of bare names.
                build_targets=("${build_targets[@]/all/ALL_BUILD}")
                build_targets=("${build_targets[@]/#/${BUILD_TARGET_FLAG} }")

                # Xcode can't restart itself if it turns out we need to reconfigure.
                # Do an advance build to handle that.
                set -x
                ${DISTCC_PUMP} "$CMAKE" --build "${build_dir}" $(cmake_config_opt $product)
                { set +x; } 2>/dev/null
            fi

            set -x
            ${DISTCC_PUMP} "$CMAKE" --build "${build_dir}" $(cmake_config_opt $product) -- ${BUILD_ARGS} ${build_targets[@]}
            { set +x; } 2>/dev/null
        fi
    done
done
# END OF BUILD PHASE

# Trap function to print the current test configuration when tests fail.
# This is a function so the text is not unnecessarily displayed when running -x.
tests_busted ()
{
    echo "*** Failed while running tests for $1 $2"
}

for deployment_target in "${STDLIB_DEPLOYMENT_TARGETS[@]}"; do
    case $deployment_target in
        linux-* | freebsd-* | macosx-*)
            # OK, we can run tests directly.
            ;;
        iphoneos-* | iphonesimulator-* | appletvos-* | appletvsimulator-* | watchos-* | watchsimulator-*)
            # FIXME: remove this
            # echo "Don't know how to run tests for $deployment_target"
            continue
            ;;
        *)
            echo "Unknown compiler deployment target: $deployment_target"
            exit 1
            ;;
    esac

    # Run the tests for each product
    for product in "${PRODUCTS[@]}"; do
        case $product in
            cmark)
                if [[ "$SKIP_TEST_CMARK" ]]; then
                    continue
                fi
                executable_target=api_test
                results_targets=(test)
                if [[ "${CMAKE_GENERATOR}" == "Xcode" ]]; then
                    # Xcode generator uses "RUN_TESTS" instead of "test".
                    results_targets=(RUN_TESTS)
                fi
                ;;
            llvm)
                continue # We don't test LLVM
                ;;
            swift)
                if [[ "$SKIP_TEST_SWIFT" ]]; then
                    continue
                fi
                executable_target=SwiftUnitTests
                results_targets=("${SWIFT_TEST_TARGETS[@]}")
                if [[ "$STRESS_TEST_SOURCEKIT" ]]; then
                    results_targets=(
                        "${results_targets[@]}"
                        stress-SourceKit
                    )
                fi
                ;;
            lldb)
                if [[ "$SKIP_TEST_LLDB" ]]; then
                    continue
                fi
                lldb_build_dir=$(build_directory $deployment_target lldb)
                swift_build_dir=$(build_directory $deployment_target swift)
                # Setup lldb executable path
                if [[ "$(uname -s)" == "Darwin" ]] ; then
                    lldb_executable="$lldb_build_dir"/$LLDB_BUILD_MODE/lldb
                else
                    lldb_executable="$lldb_build_dir"/bin/lldb
                fi

                results_dir="$lldb_build_dir/test-results"
                mkdir -p "$results_dir"
                pushd "$results_dir"

                # Handle test results formatter
                if [[ "$LLDB_TEST_WITH_CURSES" ]]; then
                    # Setup the curses results formatter.
                    LLDB_FORMATTER_OPTS="\
                                       --results-formatter lldbsuite.test.curses_results.Curses \
                                       --results-file /dev/stdout"
                else
                    LLDB_FORMATTER_OPTS="--results-file $results_dir/results.xml \
                                         -O--xpass=ignore"
                    # Setup the xUnit results formatter.
                    if [[ "$(uname -s)" != "Darwin" ]] ; then
                        # On non-Darwin, we ignore skipped tests entirely
                        # so that they don't pollute our xUnit results with
                        # non-actionable content.
                        LLDB_FORMATTER_OPTS="$LLDB_FORMATTER_OPTS -O-ndsym -O-rdebugserver -O-rlibc\\\\+\\\\+ -O-rlong.running -O-rbenchmarks -O-rrequires.one?.of.darwin"
                    fi
                fi

                SWIFTCC="$swift_build_dir/bin/swiftc" SWIFTLIBS="$swift_build_dir/lib/swift" "$LLDB_SOURCE_DIR"/test/dotest.py --executable "$lldb_executable" -C $HOST_CC $LLDB_FORMATTER_OPTS
                popd
                continue
                ;;
            llbuild)
                if [[ "$SKIP_TEST_LLBUILD" ]]; then
                    continue
                fi
                results_targets=("test")
                executable_target=""
                ;;
            swiftpm)
                if [[ "$SKIP_TEST_SWIFTPM" ]]; then
                    continue
                fi
                echo "--- Running tests for ${product} ---"
                set -x
                "${swiftpm_bootstrap_command[@]}" --build-tests test
                { set +x; } 2>/dev/null
                # As swiftpm tests itself, we break early here.
                continue
                ;;
            xctest)
                if [[ "$SKIP_TEST_XCTEST" ]]; then
                    continue
                fi
                # FIXME: We don't test xctest, yet...
                continue
                ;;
            foundation)
                if [[ "$SKIP_TEST_FOUNDATION" ]]; then
                    continue
                fi
                echo "--- Running tests for ${product} ---"
                build_dir=$(build_directory $deployment_target $product)
                XCTEST_BUILD_DIR=$(build_directory $deployment_target xctest)
                pushd "${FOUNDATION_SOURCE_DIR}"
                $NINJA_BIN TestFoundation
                LD_LIBRARY_PATH="${INSTALL_DESTDIR}"/"${INSTALL_PREFIX}"/lib/swift/:"${build_dir}/Foundation":"${XCTEST_BUILD_DIR}":$LD_LIBRARY_PATH "${build_dir}"/TestFoundation/TestFoundation
                popd
                continue
                ;;
            *)
                echo "error: unknown product: ${product}"
                exit 1
                ;;
        esac

        trap "tests_busted ${product} ''" ERR
        build_dir=$(build_directory $deployment_target $product)
        build_cmd=("$CMAKE" --build "${build_dir}" $(cmake_config_opt $product) -- ${BUILD_ARGS})

        if [[ "${executable_target}" != "" ]]; then
            echo "--- Building tests for ${product} ---"
            set -x
            ${DISTCC_PUMP} "${build_cmd[@]}" ${BUILD_TARGET_FLAG} "${executable_target}"
            { set +x; } 2>/dev/null
        fi

        echo "--- Running tests for ${product} ---"
        for target in "${results_targets[@]}"; do
            echo "--- $target ---"
            trap "tests_busted ${product} '(${target})'" ERR
            if [[ "${CMAKE_GENERATOR}" == Ninja ]] && !( "${build_cmd[@]}" --version 2>&1 | grep -i -q llbuild ); then
                # Ninja buffers command output to avoid scrambling the output
                # of parallel jobs, which is awesome... except that it
                # interferes with the progress meter when testing.  Instead of
                # executing ninja directly, have it dump the commands it would
                # run, strip Ninja's progress prefix with sed, and tell the
                # shell to execute that.
                sh -c "set -x && $("${build_cmd[@]}" -n -v ${target} | sed -e 's/[^]]*] //')"
            else
                set -x
                "${build_cmd[@]}" ${BUILD_TARGET_FLAG} ${target}
                { set +x; } 2>/dev/null
            fi
            echo "-- $target finished --"
        done

        trap - ERR
        echo "--- Finished tests for ${product} ---"
    done
done

for deployment_target in "${NATIVE_TOOLS_DEPLOYMENT_TARGETS[@]}" "${CROSS_TOOLS_DEPLOYMENT_TARGETS[@]}"; do
    set_deployment_target_based_options

    for product in "${PRODUCTS[@]}"; do

        INSTALL_TARGETS="install"

        case $product in
            cmark)
                if [[ -z "${INSTALL_CMARK}" ]] ; then
                    continue
                fi
                ;;
            llvm)
                if [[ -z "${LLVM_INSTALL_COMPONENTS}" ]] ; then
                    continue
                fi
                INSTALL_TARGETS=install-$(echo ${LLVM_INSTALL_COMPONENTS} | sed -E 's/;/ install-/g')
                ;;
            swift)
                if [[ -z "${INSTALL_SWIFT}" ]] ; then
                    continue
                fi
                ;;
            lldb)
                if [[ -z "${INSTALL_LLDB}" ]] ; then
                    continue
                fi
                case "$(uname -s)" in
                    Linux)
                        ;;
                    FreeBSD)
                        ;;
                    Darwin)
                        set_lldb_build_mode
                        pushd ${LLDB_SOURCE_DIR}
                        xcodebuild -target toolchain -configuration ${LLDB_BUILD_MODE} install ${lldb_xcodebuild_options[@]} DSTROOT="${INSTALL_DESTDIR}" LLDB_TOOLCHAIN_PREFIX="${TOOLCHAIN_PREFIX}"
                        popd
                        continue
                        ;;
                esac
                ;;
            llbuild)
                if [[ -z "${INSTALL_LLBUILD}" ]] ; then
                    continue
                fi
                INSTALL_TARGETS=install-swift-build-tool
                ;;
            swiftpm)
                if [[ -z "${INSTALL_SWIFTPM}" ]] ; then
                    continue
                fi
                if [[ -z "${INSTALL_DESTDIR}" ]] ; then
                    echo "error: --install-destdir is required"
                    exit 1
                fi

                echo "--- Installing ${product} ---"
                set -x
                "${swiftpm_bootstrap_command[@]}" --prefix="${INSTALL_DESTDIR}"/"${INSTALL_PREFIX}" install
                { set +x; } 2>/dev/null
                # As swiftpm bootstraps the installation itself, we break early here.
                continue
                ;;
            xctest)
                if [[ -z "${INSTALL_XCTEST}" ]] ; then
                    continue
                fi
                LIB_TARGET="linux"
                if [[ `uname -s` == "FreeBSD" ]]; then
                    LIB_TARGET="freebsd"
                fi
                if [[ `uname -s` == "Darwin" ]]; then
                    LIB_TARGET="macosx"
                fi
                XCTEST_INSTALL_PREFIX="${INSTALL_DESTDIR}"/"${INSTALL_PREFIX}"/lib/swift/"${LIB_TARGET}"
                echo "--- Installing ${product} ---"
                set -x
                "$XCTEST_SOURCE_DIR"/build_script.py --swiftc="${SWIFTC_BIN}" \
                                    --build-dir="${build_dir}" \
                                    --library-install-path="${XCTEST_INSTALL_PREFIX}" \
                                    --module-install-path="${XCTEST_INSTALL_PREFIX}"/"${SWIFT_HOST_VARIANT_ARCH}" \
                                    --swift-build-dir="${SWIFT_BUILD_PATH}"
                { set +x; } 2>/dev/null
                
                # As XCTest installation is self-contained, we break early here.
                continue
                ;;
            foundation)
                if [[ -z "${INSTALL_FOUNDATION}" ]] ; then
                    continue
                fi
                echo "--- Installing ${product} ---"
								build_dir=$(build_directory $deployment_target $product)
                set -x
                pushd "${FOUNDATION_SOURCE_DIR}"
                $NINJA_BIN install
                popd
                { set +x; } 2>/dev/null

                # As foundation installation is self-contained, we break early here.
                continue
                ;;
            *)
                echo "error: unknown product: ${product}"
                exit 1
                ;;
        esac

        if [[ -z "${INSTALL_DESTDIR}" ]] ; then
            echo "error: --install-destdir is required"
            exit 1
        fi

        if [ "$CROSS_COMPILE_TOOLS_DEPLOYMENT_TARGETS" ] ; then
            # If cross compiling tools, install into a deployment target specific subdirectory.
            if [[ ! "${SKIP_MERGE_LIPO_CROSS_COMPILE_TOOLS}" ]] ; then
                target_install_destdir="${BUILD_DIR}"/intermediate-install/"${deployment_target}"
            else
                target_install_destdir="${INSTALL_DESTDIR}"/"${deployment_target}"
            fi
        else
            target_install_destdir="${INSTALL_DESTDIR}"
        fi

        echo "--- Installing ${product} ---"
        build_dir=$(build_directory $deployment_target $product)

        set -x

        DESTDIR="${target_install_destdir}" "$CMAKE" --build "${build_dir}" -- ${INSTALL_TARGETS}
        { set +x; } 2>/dev/null
    done

done

if [[ "${CROSS_COMPILE_TOOLS_DEPLOYMENT_TARGETS}" ]] && [[ ! "${SKIP_MERGE_LIPO_CROSS_COMPILE_TOOLS}" ]] ; then
    echo "--- Merging and running lipo for ${CROSS_TOOLS_DEPLOYMENT_TARGETS[@]} ---"
    lipo_src_dirs=()
    for deployment_target in "${CROSS_TOOLS_DEPLOYMENT_TARGETS[@]}"; do
        lipo_src_dirs=(
            "${lipo_src_dirs[@]}"
            "${BUILD_DIR}"/intermediate-install/"${deployment_target}"
        )
    done
    "${SWIFT_SOURCE_DIR}"/utils/recursive-lipo --lipo=$(xcrun_find_tool lipo) --copy-subdirs="${INSTALL_PREFIX}/lib/swift ${INSTALL_PREFIX}/lib/swift_static" --destination="${INSTALL_DESTDIR}" ${lipo_src_dirs[@]}
fi

if [[ "${DARWIN_INSTALL_EXTRACT_SYMBOLS}" ]] ; then
    set -x
    # Copy executables and shared libraries from the INSTALL_DESTDIR to
    # INSTALL_SYMROOT and run dsymutil on them.
    (cd "${INSTALL_DESTDIR}" &&
     find ./"${TOOLCHAIN_PREFIX}" -perm -0111 -type f -print | cpio -pdm "${INSTALL_SYMROOT}")

    # Run dsymutil on executables and shared libraries.
    #
    # Exclude shell scripts.
    (cd "${INSTALL_SYMROOT}" &&
     find ./"${TOOLCHAIN_PREFIX}" -perm -0111 -type f -print | \
       grep -v swift-stdlib-tool | \
       grep -v crashlog.py | \
       grep -v symbolication.py | \
       xargs -n 1 -P $(get_dsymutil_parallelism) $(xcrun_find_tool dsymutil))

    # Strip executables, shared libraries and static libraries in
    # INSTALL_DESTDIR.
    find "${INSTALL_DESTDIR}"/"${TOOLCHAIN_PREFIX}" \
      \( -perm -0111 -or -name "*.a" \) -type f -print | \
      xargs -n 1 -P $(get_dsymutil_parallelism) $(xcrun_find_tool strip) -S

    { set +x; } 2>/dev/null
fi

if [[ "${INSTALLABLE_PACKAGE}" ]] ; then
    echo "--- Creating installable package ---"
    echo "-- Package file: ${INSTALLABLE_PACKAGE} --"
    if [[ "$(uname -s)" == "Darwin" ]] ; then
      if [ ! -f "${INSTALL_DESTDIR}/${INSTALL_PREFIX}/bin/swift-stdlib-tool" ] ; then
        echo "--- Copy swift-stdlib-tool ---"
        cp "${SWIFT_SOURCE_DIR}/utils/swift-stdlib-tool-substitute" "${INSTALL_DESTDIR}/${INSTALL_PREFIX}/bin/swift-stdlib-tool"
      fi
      
      # Create plist for xctoolchain.
      echo "-- Create Info.plist --"
      PLISTBUDDY_BIN="/usr/libexec/PlistBuddy"

      DARWIN_TOOLCHAIN_INSTALL_LOCATION="/Library/Developer/Toolchains/${DARWIN_TOOLCHAIN_NAME}.xctoolchain"
      DARWIN_TOOLCHAIN_INFO_PLIST="${INSTALL_DESTDIR}/${TOOLCHAIN_PREFIX}/Info.plist"
      DARWIN_TOOLCHAIN_REPORT_URL="https://bugs.swift.org/"

      echo "-- Removing: ${DARWIN_TOOLCHAIN_INFO_PLIST}"
      rm -f ${DARWIN_TOOLCHAIN_INFO_PLIST}

      ${PLISTBUDDY_BIN} -c "Add DisplayName string '${DARWIN_TOOLCHAIN_DISPLAY_NAME}'" "${DARWIN_TOOLCHAIN_INFO_PLIST}"
      ${PLISTBUDDY_BIN} -c "Add Version string '${DARWIN_TOOLCHAIN_VERSION}'" "${DARWIN_TOOLCHAIN_INFO_PLIST}"
      ${PLISTBUDDY_BIN} -c "Add CFBundleIdentifier string '${DARWIN_TOOLCHAIN_BUNDLE_IDENTIFIER}'" "${DARWIN_TOOLCHAIN_INFO_PLIST}"
      ${PLISTBUDDY_BIN} -c "Add ReportProblemURL string '${DARWIN_TOOLCHAIN_REPORT_URL}'" "${DARWIN_TOOLCHAIN_INFO_PLIST}"
      ${PLISTBUDDY_BIN} -c "Add OverrideEnvironment::DYLD_LIBRARY_PATH string '${DARWIN_TOOLCHAIN_INSTALL_LOCATION}/usr/lib'" "${DARWIN_TOOLCHAIN_INFO_PLIST}"
      chmod a+r "${DARWIN_TOOLCHAIN_INFO_PLIST}"

      if [[ "${DARWIN_TOOLCHAIN_APPLICATION_CERT}" ]] ; then
        echo "-- Codesign xctoolchain --"
        "${SWIFT_SOURCE_DIR}/utils/toolchain-codesign" "${DARWIN_TOOLCHAIN_APPLICATION_CERT}" "${INSTALL_DESTDIR}/${TOOLCHAIN_PREFIX}" 
      fi
      if [[ "${DARWIN_TOOLCHAIN_INSTALLER_PACKAGE}" ]] ; then
        echo "-- Create Installer --"
        "${SWIFT_SOURCE_DIR}/utils/toolchain-installer" "${INSTALL_DESTDIR}/${TOOLCHAIN_PREFIX}" "${DARWIN_TOOLCHAIN_BUNDLE_IDENTIFIER}" \
        "${DARWIN_TOOLCHAIN_INSTALLER_CERT}" "${DARWIN_TOOLCHAIN_INSTALLER_PACKAGE}" "${DARWIN_TOOLCHAIN_INSTALL_LOCATION}" \
        "${DARWIN_TOOLCHAIN_VERSION}" "${SWIFT_SOURCE_DIR}/utils/darwin-installer-scripts"
      fi 

      (cd "${INSTALL_DESTDIR}" &&
        tar -c -z -f "${INSTALLABLE_PACKAGE}" "${TOOLCHAIN_PREFIX/#\/}")
    else
      (cd "${INSTALL_DESTDIR}" &&
        tar -c -z -f "${INSTALLABLE_PACKAGE}" --owner=0 --group=0 "${INSTALL_PREFIX/#\/}")
    fi
    if [[ "${TEST_INSTALLABLE_PACKAGE}" ]] ; then
        PKG_TESTS_SOURCE_DIR="${WORKSPACE}/swift-package-tests"
        PKG_TESTS_SANDBOX_PARENT="/tmp/swift_package_sandbox"

        if [[ "$(uname -s)" == "Darwin" ]] ; then
            PKG_TESTS_SANDBOX="${PKG_TESTS_SANDBOX_PARENT}"/"${TOOLCHAIN_PREFIX}"
        else # Linux
            PKG_TESTS_SANDBOX="${PKG_TESTS_SANDBOX_PARENT}"
        fi

        LIT_EXECUTABLE_PATH="${LLVM_SOURCE_DIR}/utils/lit/lit.py"
        FILECHECK_EXECUTABLE_PATH="$(build_directory_bin $deployment_target llvm)/FileCheck"
        echo "-- Test Installable Package --"
        set -x
        rm -rf "${PKG_TESTS_SANDBOX_PARENT}"
        mkdir -p "${PKG_TESTS_SANDBOX}"
        pushd "${PKG_TESTS_SANDBOX_PARENT}"
        tar xzf "${INSTALLABLE_PACKAGE}"
        popd

        (cd "${PKG_TESTS_SOURCE_DIR}" &&
                python "${LIT_EXECUTABLE_PATH}" . -sv --param package-path="${PKG_TESTS_SANDBOX}" --param filecheck="${FILECHECK_EXECUTABLE_PATH}")
        { set +x; } 2>/dev/null
    fi
fi

if [[ "${SYMBOLS_PACKAGE}" ]] ; then
    echo "--- Creating symbols package ---"
    echo "-- Package file: ${SYMBOLS_PACKAGE} --"
    if [[ "$(uname -s)" == "Darwin" ]] ; then
      (cd "${INSTALL_SYMROOT}" &&
        tar -c -z -f "${SYMBOLS_PACKAGE}" "${TOOLCHAIN_PREFIX/#\/}")
    else
      (cd "${INSTALL_SYMROOT}" &&
        tar -c -z -f "${SYMBOLS_PACKAGE}" --owner=0 --group=0 "${INSTALL_PREFIX/#\/}")
    fi
fi

# FIXME(before commit): assertion modes:
# On:
#   SWIFT_VERIFY_ALL:BOOL=TRUE
# Off:
#   SWIFT_VERIFY_ALL:BOOL=FALSE

#>