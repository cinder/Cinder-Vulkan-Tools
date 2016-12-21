#!/bin/bash

VulkanSDK=/c/VulkanSDK/1.0.37.0
CMakeFile=$VulkanSDK/glslang/CMakeLists.txt
ScriptDir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

sed -i -- 's/^\(\s\+\)\(set(\s*CMAKE_DEBUG_POSTFIX\s*"d"\s*)\)/\1#\2/' $CMakeFile

Lines="add_definitions(-DGLSLANG_OSINCLUDE_WIN32) #EOL\n\
    # Override the default /MD with /MT\n\
    foreach(\n\
        flag_var\n\
        CMAKE_C_FLAGS CMAKE_C_FLAGS_DEBUG CMAKE_C_FLAGS_RELEASE CMAKE_C_FLAGS_MINSIZEREL CMAKE_C_FLAGS_RELWITHDEBINFO\n\
        CMAKE_CXX_FLAGS CMAKE_CXX_FLAGS_DEBUG CMAKE_CXX_FLAGS_RELEASE CMAKE_CXX_FLAGS_MINSIZEREL CMAKE_CXX_FLAGS_RELWITHDEBINFO\n\
    )\n\
        if( \${flag_var} MATCHES \"/MD\" )\n\
            string( REGEX REPLACE \"/MD\" \"/MT\" \${flag_var} \"\${\${flag_var\}}\" )\n\
        endif()\n\
    endforeach()\n\
    message( \"Overrode /MD and /MDd with /MT and MTd, respectively\" )"
sed -i -- "s|add_definitions(\s*-DGLSLANG_OSINCLUDE_WIN32\s*)\s*$|${Lines}|" $CMakeFile

function copy_file {
    local SRC=$1/$3
    local DST=$2/$3
    if [ ! -f "$SRC" ]; then
        echo "Source file does not exist: $SRC"
        exit 1
    fi
	SRC=`realpath $SRC`
	DST=`realpath $DST`
    echo -e "\tcp $SRC $DST"
    cp $SRC $DST
}

function copy_libs {
	local CONFIG=$3
	local SRC=$1
	local DST=$2/$CONFIG

	mkdir -p $DST
	SRC=`realpath $SRC`
	DST=`realpath $DST`

	echo "Copying $CONFIG files from $SRC to $DST"

    copy_file $SRC/glslang/$CONFIG $DST glslang.lib
    copy_file $SRC/glslang/OSDependent/Windows/$CONFIG $DST OSDependent.lib
    copy_file $SRC/OGLCompilersDLL/$CONFIG $DST OGLCompiler.lib
    copy_file $SRC/SPIRV/$CONFIG $DST SPIRV.lib
    copy_file $SRC/hlsl/$CONFIG $DST HLSL.lib
    echo ""
}

function copy_headers {
	local PARENT=$1
	local SUB=$2
	local DSTDIR=$3

	cd $PARENT
	for file in `find $SUB -type f -name "*.h"`; do
		SRC=`dirname "$PARENT/$file"`
		DST=`dirname "$DSTDIR/$file"`
		BASE=`basename "$PARENT/$file"`

		if [ ! -d "$DST" ]; then
			mkdir -p $DST
		fi		

		SRC=`realpath $SRC`
		DST=`realpath $DST`
		
		copy_file $SRC $DST $BASE
	done
}

function build_libs {
	local Target=$1
	local MSBuildExe=$2
	case $Target in
		"vc2013-x86")
			Generator="Visual Studio 12 2013"
			Toolset=v120
			PlatformTarget=x86
		;;

		"vc2013-x64")
			Generator="Visual Studio 12 2013 Win64"
			Toolset=v120
			PlatformTarget=x64
		;;

		"vc2015-x86")
			Generator="Visual Studio 14 2015"
			Toolset=v140
			PlatformTarget=x64
		;;

		"vc2015-x64")
			Generator="Visual Studio 14 2015 Win64"
			Toolset=v140
			PlatformTarget=x64
		;;
	esac

	if [ ! -z "$Generator" ] ; then
		BuildDir=$VulkanSDK/glslang/build-$Target
		if [ -d $BuildDir ]; then 
			rm -rf $BuildDir
			echo "Removed existing $BuildDir"
		fi
		mkdir -p $BuildDir
		cd $BuildDir
		echo -e "Generating for $Generator"
		cmake -G "$Generator" ..

		NPROC=`nproc`
		"$MSBuildExe" /maxcpucount:$NPROC /property:Configuration=Debug "$BuildDir/glslang.sln"
		"$MSBuildExe" /maxcpucount:$NPROC /property:Configuration=Release "$BuildDir/glslang.sln"
		
		copy_libs $BuildDir $ScriptDir/../../lib/msw/$PlatformTarget/$Toolset Debug 
		copy_libs $BuildDir $ScriptDir/../../lib/msw/$PlatformTarget/$Toolset Release

		echo "Copying Vulkan libs"
		case $Target in
			"vc2013-x86")
			;;

			"vc2013-x64")
			;;

			"vc2015-x86")
			;;

			"vc2015-x64")
				copy_file $VulkanSDK/Bin $ScriptDir/../../lib/msw/$PlatformTarget/$Toolset VKstatic.1.lib
				copy_file $VulkanSDK/Bin $ScriptDir/../../lib/msw/$PlatformTarget/$Toolset vulkan-1.lib
			;;
		esac
		echo ""

		echo "Copying headers"
		copy_headers $VulkanSDK/glslang glslang $ScriptDir/../../include
		copy_file $VulkanSDK/glslang/SPIRV $ScriptDir/../../include/SPIRV GlslangToSpv.h
		copy_file $VulkanSDK/glslang/SPIRV $ScriptDir/../../include/SPIRV Logger.h
		copy_file $VulkanSDK/Include/vulkan $ScriptDir/../../include/vulkan vk_platform.h
		copy_file $VulkanSDK/Include/vulkan $ScriptDir/../../include/vulkan vulkan.h
	fi
}

#MSBuildExe=/c/Program\ Files\ \(x86\)/MSBuild/12.0/Bin/MSBuild.exe
#if [ -f "$MSBuildExe" ]; then
#	echo "Processing for v120"
#	build_libs "vc2013-x86" "$MSBuildExe"
#	build_libs "vc2013-x64" "$MSBuildExe"
#fi

MSBuildExe=/c/Program\ Files\ \(x86\)/MSBuild/14.0/Bin/MSBuild.exe
if [ -f "${MSBuildExe}" ]; then
	echo "Processing for v140"
	#build_libs "vc2015-x86" "$MSBuildExe"
	build_libs "vc2015-x64" "$MSBuildExe"
fi
