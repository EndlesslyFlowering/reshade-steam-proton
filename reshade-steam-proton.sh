#!/bin/bash
cat > /dev/null <<LICENSE
    Copyright (C) 2021-2022  kevinlekiller

    This program is free software; you can redistribute it and/or
    modify it under the terms of the GNU General Public License
    as published by the Free Software Foundation; either version 2
    of the License, or (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program; if not, write to the Free Software
    Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
    https://www.gnu.org/licenses/old-licenses/gpl-2.0.en.html
LICENSE
cat > /dev/null <<DESCRIPTION
    Bash script to download ReShade and the shaders and link them to Steam games on Linux.
    By linking, we can re-run this script and all the games automatically get the newest ReShade and
    shader versions.

    Environment Variables:
        D3DCOMPILER
            To skip installing d3dcompiler_47, set D3DCOMPILER=0 ; ex.: D3DCOMPILER=0 ./reshade-steam-proton.sh

        MAIN_PATH
            By default, ReShade / shader files are stored in ~/.reshade
            You can override this by setting the MAIN_PATH variable, for example: MAIN_PATH=~/Documents/reshade ./reshade-steam-proton.sh

    Reuirements:
        grep
        curl
        7z
        wget
        protontricks
        git

    Optional:
        objdump

    Notes:
        Overriding and installing the d3dcompiler_47 dll seems to occasionally fail with proton-ge under protontricks, switch
        to Steam's proton before running, you can switch back to proton-ge after.

        OpenGL games like Wolfenstein: The New Order, require the dll to be named opengl32.dll
        You will want to respond 'n' when asked for automatic detection of the dll.
        Then you will write 'opengl32' when asked for the name of the dll to override.
        You can check on pcgamingwiki.com to see what graphic API the game uses.

    Usage:
        Download the script
            Using wget:
                wget https://github.com/kevinlekiller/reshade-steam-proton/raw/main/reshade-steam-proton.sh
            Using git:
                git clone https://github.com/kevinlekiller/reshade-steam-proton
                cd reshade-steam-proton
        Make it executable:
            chmod u+x reshade-steam-proton.sh
        Run it:
            ./reshade-steam-proton.sh

        Installing ReShade for a game:
            Example on Back To The Future Episode 1:

                If the game has never been run, run it, steam will create the various required directories.
                Exit the game.

                Find the SteamID: protontricks -s Back To The Future
                    Back to the Future: Ep 1 - It's About Time (31290)

                Find the game directory where the .exe file is.
                    You can open the Steam client, right click the game, click Properties,
                    click Local Files, clicking Browse, find the directory with the main
                    exe file, copy it, supply it to the script.

                    Or you can run : find ~/.local -iname 'Back to the future*'
                    Then run : ls "/home/kevin/.local/share/Steam/steamapps/common/Back to the Future Ep 1"
                    We see BackToTheFuture101.exe is in this directory.

                Run this script.

                Type i to install ReShade.
                    If you have never run this script, the shaders and ReShade will be downloaded.

                Supply the game directory where exe file is, when asked:
                    /home/kevin/.local/share/Steam/steamapps/common/Back to the Future Ep 1

                Select if you want it to automatically detect the correct dll file for ReShade or
                to manually specity it.

                Give it 31290 when asked for the SteamID

                If the automatic override of the dll fails, you will be
                instructed how to manually do it.

                Run the game, set the Effects and Textures search paths in the ReShade settings.

        Uninstalling ReShade for a game:
            Run this script.

            Type u to uninstall ReShade.

            Supply the game path where the .exe file is (see instructions above).

            Supply the SteamID for the game (see instructions above).

        Removing ReShade / shader files:
            By default the files are stored in ~/.reshade
            Run: rm -rf ~/.reshade
DESCRIPTION

function printErr() {
    if [[ -d $tmpDir ]]; then
        rm -rf "$tmpDir"
    fi
    echo -e "Error: $1\nExiting."
    [[ -z $2 ]] && exit 1 || exit "$2"
}

function checkStdin() {
    while true; do
        read -rp "$1" userInput
        if [[ $userInput =~ $2 ]]; then
            break
        fi
    done
    echo "$userInput"
}

function updateReShade() {
    echo -e "$SEPERATOR\nUpdating default ReShade shaders."
    cd "$RESHADE_DEFAULT_SHADERS_PATH" || printErr "reshade-shaders folder missing."
    git pull || printErr "Could not update default ReShade shaders."

    echo -e "$SEPERATOR\nChecking for ReShade updates."
    RVERS=$(curl -sL https://reshade.me | grep -Po "downloads/ReShade_Setup_[\d.]+\.exe" | head -n1)
    if [[ $RVERS == "" ]]; then
        printErr "Could not fetch ReShade version."
    fi
    if [[ $RVERS != "$VERS" ]]; then
        echo "Updating Reshade."
        tmpDir=$(mktemp -d)
        cd "$tmpDir" || printErr "Failed to create temp directory."
        wget -q https://reshade.me/"$RVERS" || printErr "Could not download latest version of ReShade."
        exeFile="$(find . -name "*.exe")"
        if ! [[ -f $exeFile ]]; then
            printErr "Download of ReShade exe file failed."
        fi
        7z -y e "$exeFile" 1> /dev/null || printErr "Failed to extract ReShade using 7z."
        rm -f "$exeFile"
        rm -rf "${RESHADE_PATH:?}"/*
        mv ./* "$RESHADE_PATH/"
        cd "$MAIN_PATH" || exit
        echo "$RVERS" > VERS
        rm -rf "$tmpDir"
    else
        echo "ReShade is already up to date."
    fi
}

function uninstallReShade() {
    echo "$SEPERATOR"
    getGamePath
    getSteamID
    echo "Unlinking ReShade files."
    LINKS="$(echo "$COMMON_OVERRIDES" | sed 's/ /.dll /g' | sed 's/$/.dll/') Shaders Textures ReShade.ini ReShade.log ReShadePreset.ini"
    for link in $LINKS; do
        if [[ -L $gamePath/$link ]]; then
            echo "Unlinking \"$gamePath/$link\"."
            unlink "$gamePath/$link"
        fi
    done

    echo "Removing dll overrides."
    checkUserReg "remove overrides for ${COMMON_OVERRIDES// /, })"
    if [[ -f $regFile ]]; then
        for override in $COMMON_OVERRIDES; do
            pattern=${OVERRIDE_REGEX//OVERRIDE/$override}
            if [[ $(grep -Po "$pattern" "$regFile") != "" ]]; then
                pattern="s/$pattern\n//g"
                echo "Removing dll override for \"$override\"."
                sed -zi "$pattern" "$regFile"
            fi
        done
    fi

    echo "Removing ReShade Vulkan layer."
    regCmd="wine reg DELETE \"HKLM\SOFTWARE\Khronos\Vulkan\ImplicitLayers\" /f"
    $PROTONTRICKS -c "$regCmd /reg:64" $SteamID
    $PROTONTRICKS -c "$regCmd /reg:32" $SteamID

    echo "Finished uninstalling ReShade for SteamID $SteamID."
    exit 0
}

function getShaderRepos() {
    cd "$SHADER_REPOS_PATH"

    local allShaderRepos=($(ls -d */ | cut -f1 -d'/'))
    shaderRepos=()
    for i in ${allShaderRepos[@]}; do
        if [[ $i != "reshade-shaders" ]]; then
            shaderRepos+=( $i )
        fi
    done
}

function updateActiveShaders() {
    echo -e "$SEPERATOR\nUpdating active shaders..."

    getShaderRepos

    cd "$RESHADE_SHADERS_PATH/Shaders"
    rm -rf *
    cd "$RESHADE_SHADERS_PATH/Textures"
    rm -rf *

    echo -e "$SEPERATOR
Do you want to add the default ReShade shaders to your active shaders?
\"ReShade.fxh\" and \"ReShadeUI.fxh\" will always be added."
    if [[ $(checkStdin "(y/n): " "^(y|n)$") == "y" ]]; then
        for stuff in "$RESHADE_DEFAULT_SHADERS_PATH/Shaders/"*; do
            ln -s "$stuff" "$RESHADE_SHADERS_PATH/Shaders/" \
            || printErr "Could not link Shaders of the default repository."
        done
        for stuff in "$RESHADE_DEFAULT_SHADERS_PATH/Textures/"*; do
            ln -s "$stuff" "$RESHADE_SHADERS_PATH/Textures/" \
            || printErr "Could not link Textures of the default repository."
        done
    else
        ln -s "$RESHADE_DEFAULT_SHADERS_PATH/Shaders/ReShade.fxh"   "$RESHADE_SHADERS_PATH/Shaders/"
        ln -s "$RESHADE_DEFAULT_SHADERS_PATH/Shaders/ReShadeUI.fxh" "$RESHADE_SHADERS_PATH/Shaders/"
    fi

    for i in ${shaderRepos[@]}; do
        echo -e "$SEPERATOR\nAdding \"$i\"..."
        if [[ -d "$SHADER_REPOS_PATH/$i/Shaders" ]]; then
            for stuff in "$SHADER_REPOS_PATH/$i/Shaders/"*; do
                ln -s "$stuff" "$RESHADE_SHADERS_PATH/Shaders/" \
                || printErr "Could not link Shaders of repository \"$i\"."
            done
        else
            printErr "No Shaders folder present in repository \"$i\""
        fi
        if [[ -d "$SHADER_REPOS_PATH/$i/Textures" ]]; then
            for stuff in "$SHADER_REPOS_PATH/$i/Textures/"*; do
                ln -s "$stuff" "$RESHADE_SHADERS_PATH/Textures/" \
                || printErr "Could not link Textures of repository \"$i\"."
            done
        fi
    done
}

function addShaderRepos() {
    while true; do
        cd "$SHADER_REPOS_PATH"
        echo -e "$SEPERATOR\nSupply a github link to a repository that hosts shaders (example: https://github.com/crosire/reshade-shaders)."
        read -rp 'github link: ' ghLink
        ghLink=$(echo "$ghLink" | sed 's/\.git//')
        ghLink=$(echo "$ghLink" | sed 's/\/$//')
        repoName=$(echo "$ghLink" | sed 's/.\+\///')

        getShaderRepos

        for i in ${shaderRepos[@]}; do
            if [[ $repoName == $i ]]; then
                duplicate=true
                break
            fi
        done

        if [[ $duplicate != true ]]; then
            git clone $ghLink || printErr "Could not clone repository."
            cd "$repoName" || printErr "The repository folder was not found."

            updateActiveShaders
        else
            echo -e "$SEPERATOR\nRepository already added!"
        fi

        echo -e "$SEPERATOR\nAdd another repository?"
        if [[ $(checkStdin "(y/n): " "^(y|n)$") == "y" ]]; then
            echo "$SEPERATOR"
            continue
        else
            break
        fi
    done
}

function updateShaderRepos() {
    getShaderRepos

    echo -e "$SEPERATOR\nUpdating all shader repositories..."

    for i in ${shaderRepos[@]}; do
        echo -e "$SEPERATOR\nUpdating \"$i\"..."
        cd "$SHADER_REPOS_PATH/$i" || printErr "Could not find shader repository folder \"$i\""
        git pull || printErr "Could not update shader repository \"$i\""
    done

    updateActiveShaders

    echo -e "$SEPERATOR\nDone."
}

function removeShaderRepos() {
    while true; do
        cd "$SHADER_REPOS_PATH"
        getShaderRepos
        echo -e "$SEPERATOR\nWhich repository do you want to remove?"
        for i in ${shaderRepos[@]}; do
            echo "- $i"
        done
        read -rp 'repository name: ' repoName

        if [[ -d $repoName ]]; then
            echo -e "$SEPERATOR\nRemoving $repoName..."
            rm -rf "$repoName"

            updateActiveShaders
        else
            echo "repository name not found."
        fi

        echo -e "$SEPERATOR\nRemove another repository?"
        if [[ $(checkStdin "(y/n): " "^(y|n)$") == "y" ]]; then
            echo "$SEPERATOR"
            continue
        else
            break
        fi
    done
}

function getGamePath() {
    echo 'Supply the folder path where the main executable (exe file) for the game is.'
    echo 'On default steam settings, look in ~/.local/share/Steam/steamapps/common/'
    echo '(Control+c to exit)'
    while true; do
        read -rp 'Game path: ' gamePath
        eval gamePath="$gamePath"
        gamePath=$(realpath "$gamePath")

        if ! ls "$gamePath" > /dev/null 2>&1 || [[ -z $gamePath ]]; then
            echo "Incorrect or empty path supplied. You supplied \"$gamePath\"."
            continue
        fi

        if ! ls "$gamePath/"*.exe > /dev/null 2>&1; then
            echo "No .exe file found in \"$gamePath\"."
            echo "Do you still want to use this directory?"
            if [[ $(checkStdin "(y/n): " "^(y|n)$") != "y" ]]; then
                continue
            fi
        fi

        echo "Is this path correct? \"$gamePath\""
        if [[ $(checkStdin "(y/n): " "^(y|n)$") == "y" ]]; then
            break
        fi
    done
}

function getSteamID() {
    echo -e "$SEPERATOR\nPlease supply the SteamID of the game (To find the SteamID, run: protontricks -s Name_Of_Game)."
    echo '(Control+c to exit)'
    SteamID=$(checkStdin "SteamID: " "^[0-9]*$")
}

function checkUserReg() {
    regFile=~/".local/share/Steam/steamapps/compatdata/$SteamID/pfx/user.reg"
    if [[ ! -f $regFile ]]; then
        echo -e "$SEPERATOR\nCould not modify or find user.reg file: \"$regFile\""
        regFile=
        echo "Manually run: protontricks $SteamID winecfg"
        echo "In the Libraries tab, $1."
        read -rp 'Press any key to continue.'
    fi
}

function autoGetExeArch() {
    exeArch=32
    for file in "$gamePath/"*.exe; do
        if [[ $(file "$file") =~ x86-64 ]]; then
            exeArch=64
            break
        fi
    done

    echo -e "$SEPERATOR\nWe have detected the game is $exeArch bits, is this correct?"
    if [[ $(checkStdin "(y/n): " "^(y|n)$") == "n" ]]; then
        echo "Specify if the game's EXE file architecture is 32 or 64 bits:"
        [[ $(checkStdin "(32/64) " "^(32|64)$") == 64 ]] && exeArch=64 || exeArch=32
    fi
}

function checkPCGW() {
    echo "Also check the entry for the game on https://www.pcgamingwiki.com/ if unsure."
}

function enterManualDllOverride() {
    checkPCGW
    while true; do
        read -rp 'Override: ' wantedDll
        wantedDll=${wantedDll//.dll/}
        echo "You have entered '$wantedDll', is this correct?"
        read -rp '(y/n): ' ynCheck
        if [[ $ynCheck =~ ^(y|Y|yes|YES)$ ]]; then
            break
        fi
    done
}

function addDllOverride() {
    if [[ -f $regFile ]] && [[ $(grep -Po "^\"${1}\"=\"native,builtin\"" "$regFile") == "" ]]; then
        echo -e "$SEPERATOR\nAdding dll override for ${1}."
        api="$1"
        sed -ie '/\[Software\\\\Wine\\\\DllOverrides\].*/a \"'$api'\"=\"native,builtin\"' "$regFile"
    fi
}

function setupReShadeFiles() {
    echo -e "$SEPERATOR\nLinking ReShade files to game directory."

    presetPath="${PRESETS_PATH}/${SteamID}.ini"
    logPath="${LOGS_PATH}/${SteamID}.log"

    touch "$(realpath $presetPath)"
    touch "$(realpath $logPath)"

    ln -is "$(realpath $INI_PATH)"   "$gamePath/ReShade.ini"
    ln -is "$(realpath $presetPath)" "$gamePath/ReShadePreset.ini"
    ln -is "$(realpath $logPath)"    "$gamePath/ReShade.log"
    ln -is "$(realpath "$MAIN_PATH"/reshade-shaders/Textures)" "$gamePath/"
    ln -is "$(realpath "$MAIN_PATH"/reshade-shaders/Shaders)"  "$gamePath/"
}

function installVulkan() {
    echo "Does the game use the Vulkan API? (using Proton 8.0 or later is required!)"
    if [[ $(checkStdin "(y/n): " "^(y|n)$") == "y" ]]; then

#        if [[ -z ${DISPLAY}${WAYLAND_DISPLAY} ]]; then
#            printErr "Please run the script from the Desktop."
#            exit 1
#
#        else

            #EXECUTION ORDER MATTERS!
            #dll override needs to be added before protontricks is called

            checkUserReg "Add \"vulkan-1\" and make sure it is set to \"native,builtin\"."

            addDllOverride "vulkan-1"

#            echo -e "$SEPERATOR\nInstalling VCRedist 2022..."
#
#            $PROTONTRICKS --no-runtime --background-wineserver -c "winetricks -f -q vcrun2022" $SteamID 2>/dev/null

            cd "$VULKAN_RT_DL_PATH"

            echo -e "$SEPERATOR\nGetting latest Vulkan version..."

            LATEST_VULKAN_VER=$(curl -s https://vulkan.lunarg.com/sdk/latest/windows.json | grep -Po "\d+\.\d+\.\d+\.\d+")

            if [[ $? != 0 ]]; then
                printErr "Could not get latest Vulkan version."
            fi

            echo "Latest Vulkan version is: $LATEST_VULKAN_VER"

            echo -e "$SEPERATOR\nDownloading latest Vulkan Runtime..."
            VULKAN_RT_INSTALLER="VulkanRT-$LATEST_VULKAN_VER-Installer.exe"

            if [[ ! -f $VULKAN_RT_INSTALLER ]]; then
                curl -sLO https://sdk.lunarg.com/sdk/download/$LATEST_VULKAN_VER/windows/$VULKAN_RT_INSTALLER \
                || printErr "Could not download latest Vulkan Runtime."
            else
                echo "Latest version already downloaded."
            fi

            echo -e "\nInstalling latest Vulkan Runtime..."

            $PROTONTRICKS_LAUNCH --no-runtime --background-wineserver --appid $SteamID "$VULKAN_RT_DL_PATH/$VULKAN_RT_INSTALLER" /S 2>/dev/null \
            || printErr "Could not install latest Vulkan Runtime."

            echo -e "$SEPERATOR\nInstalling ReShade's Vulkan layer..."

            regCmd="wine reg ADD \"HKLM\SOFTWARE\Khronos\Vulkan\ImplicitLayers\" /d 0 /t REG_DWORD /v \"Z:\home\\${USER}\.reshade\reshade\ReShade${exeArch}.json\" /f /reg:${exeArch}"
            $PROTONTRICKS --no-runtime --background-wineserver -c "${regCmd}" ${SteamID} 2>/dev/null \
            || printErr "Could not install ReShade's Vulkan layer."

            setupReShadeFiles

#            echo "Run the game once and then execute this:"
#            echo "protontricks -c \"wine reg ADD \\\"HKLM\SOFTWARE\Khronos\Vulkan\ImplicitLayers\\\" /d 0 /t REG_DWORD /v \\\"Z:\home\\${USER}\.reshade\reshade\ReShade${exeArch}.json\\\" /f /reg:64\" $SteamID"
#        fi

        if [[ $? == 0 ]]; then
            echo "Done."
            exit 0
        else
            echo "An error has occured."
            exit 1
        fi
    fi
}


SEPERATOR="------------------------------------------------------------------------------------------------"

OVERRIDE_REGEX='"OVERRIDE"="native,builtin"'
COMMON_OVERRIDES="d3d8 d3d9 d3d11 d3d12 ddraw dinput8 dxgi opengl32 vulkan-1"

echo -e "$SEPERATOR\nReShade installer/updater for Steam and proton on Linux.\n$SEPERATOR\n"

MAIN_PATH=${MAIN_PATH:-~/".reshade"}
MAIN_PATH="$(realpath $MAIN_PATH)"
RESHADE_PATH="$MAIN_PATH/reshade"
RESHADE_SHADERS_PATH="$MAIN_PATH/reshade-shaders"
SHADER_REPOS_PATH="$MAIN_PATH/shader-repos"
RESHADE_DEFAULT_SHADERS_PATH="$SHADER_REPOS_PATH/reshade-shaders"
INI_PATH="$MAIN_PATH/ReShade.ini"
LOGS_PATH="$MAIN_PATH/logs"
PRESETS_PATH="$MAIN_PATH/presets"

VULKAN_RT_DL_PATH="/home/$USER/Downloads"

mkdir -p "$MAIN_PATH" || printErr "Unable to create directory '$MAIN_PATH'."
cd "$MAIN_PATH" || exit

mkdir -p "$RESHADE_PATH"      || printErr "Unable to create directory '$RESHADE_PATH'."
mkdir -p "$SHADER_REPOS_PATH" || printErr "Unable to create directory '$SHADER_REPOS_PATH'."
mkdir -p "$PRESETS_PATH"      || printErr "Unable to create directory '$PRESETS_PATH'."
mkdir -p "$LOGS_PATH"         || printErr "Unable to create directory '$LOGS_PATH'."

mkdir -p "$RESHADE_SHADERS_PATH/Shaders"  || printErr "Unable to create directory '$RESHADE_SHADERS_PATH/Shaders'."
mkdir -p "$RESHADE_SHADERS_PATH/Textures" || printErr "Unable to create directory '$RESHADE_SHADERS_PATH/Textures'."

#check if protontricks is installed
flatpak info --show-ref com.github.Matoking.protontricks 1>/dev/null 2>/dev/null
if [[ $? == 0 ]]; then
    PROTONTRICKS="flatpak run com.github.Matoking.protontricks"
    PROTONTRICKS_LAUNCH="flatpak run --command=protontricks-launch com.github.Matoking.protontricks"
else
    hash protontricks 1>/dev/null 2>/dev/null || printErr "protontricks not found!"
    hash protontricks-launch 1>/dev/null 2>/dev/null || printErr "protontricks-launch not found!"
    PROTONTRICKS="protontricks"
    PROTONTRICKS_LAUNCH="protontricks-launch"
fi

hash objdump
if [[ $? == 0 ]]; then
    GET_WANTED_DLL="objdump -x"
else
    hash strings || echo "Auto detection of DLLs needed disabled as both \"objdump\" and \"string\" were not found."
    if [[ $? == 0 ]]; then
        GET_WANTED_DLL="strings"
    else
        GET_WANTED_DLL=""
    fi
fi

#create default ReShade.ini if needed
if [[ ! -f $INI_PATH ]]; then
    echo -e "[GENERAL]\nEffectSearchPaths=.\Shaders\**\nTextureSearchPaths=.\Textures\**" > "$INI_PATH" \
    || printErr "While trying to create the default ReShade.ini."
    unix2dos "$INI_PATH" 2>/dev/null 1>/dev/null \
    || printErr "While trying to create the default ReShade.ini."
fi

D3DCOMPILER=${D3DCOMPILER:-1}

#install default ReShade shaders if not already installed
if [[ ! -d "$RESHADE_DEFAULT_SHADERS_PATH" ]]; then
    echo -e "Installing default ReShade shaders.\n$SEPERATOR"
    cd "$SHADER_REPOS_PATH"
    git clone --branch slim https://github.com/crosire/reshade-shaders \
    || printErr "Unable to clone https://github.com/crosire/reshade-shaders"
fi

#install ReShade if not already installed
[[ -f VERS ]] && VERS=$(cat VERS) || VERS=0

if [[ ! -f reshade/ReShade64.dll ]]  || \
   [[ ! -f reshade/ReShade32.dll ]]  || \
   [[ ! -f reshade/ReShade64.json ]] || \
   [[ ! -f reshade/ReShade32.json ]]; then
    updateReShade
fi

while true; do
    cd "$MAIN_PATH"

    echo -e "What do you want to do?
- (i)nstall or (u)ninstall ReShade for a game
- update ReShade (ru)
- add shader repositories (sa)
- update shader repositories (su)
- remove shader repositories (sr)
(Control+c to exit)\n"

    doWhat=$(checkStdin "(i/u/ru/sa/su/sr): " "^(i|u|ru|sa|su|sr)$")

    if [[ $doWhat == "i" ]]; then
        echo -e "$SEPERATOR\n"
        break
    elif [[ $doWhat == "u" ]]; then
        uninstallReShade
        #function exits itself
    elif [[ $doWhat == "ru" ]]; then
        updateReShade
        echo -e "$SEPERATOR\n"
    elif [[ $doWhat == "sa" ]]; then
        addShaderRepos
        echo -e "$SEPERATOR\n"
    elif [[ $doWhat == "su" ]]; then
        updateShaderRepos
        echo -e "$SEPERATOR\n"
    elif [[ $doWhat == "sr" ]]; then
        removeShaderRepos
        echo -e "$SEPERATOR\n"
    fi
done

getGamePath

autoGetExeArch

getSteamID

installVulkan

echo "Do you want the script to attempt to automatically detect the right dll to use for ReShade?"

[[ $(checkStdin "(y/n): " "^(y|n)$") == "y" ]] && wantedDll="auto" || wantedDll="manual"

if [[ $wantedDll == "auto" ]]; then

    if [[ $GET_WANTED_DLL != "" ]]; then
        if [[ $exeArch -eq 64 ]]; then
            exeInternalArch="x86-64"
        else
            exeInternalArch="80386"
        fi

        possibleWantedDlls=()

        for file in "$gamePath/"{*.exe,*.dll} "$gamePath/"**/{*.exe,*.dll}; do
            if [[ $(file "$file") =~ $exeInternalArch ]]; then
                testDlls=$($GET_WANTED_DLL "${file}" | grep -Po "[^ ]*\.[DdLl]{3}" | tr '[:upper:]' '[:lower:]')

                for override in $COMMON_OVERRIDES; do
                    for testDll in $testDlls; do
                        if [[ $testDll == *"$override"* ]]; then
                            possibleWantedDlls+=( $testDll )
                        fi
                    done
                done
            fi
        done

        echo "$SEPERATOR"

        if [[ ${#possibleWantedDlls[@]} -eq 0 ]]; then
            echo "No dlls detected. Switching to manual mode."
            wantedDll="manual"
        elif [[ ${#possibleWantedDlls[@]} -eq 1 ]]; then
            echo "We have detected the game needs \"${possibleWantedDlls[0]}\" as dll override, is this correct?"
            checkPCGW
            if [[ $(checkStdin "(y/n): " "^(y|n)$") == "n" ]]; then
                wantedDll="manual"
            else
                wantedDll="${possibleWantedDlls[0]}"
            fi
        elif [ ${#possibleWantedDlls[@]} -eq 2 ] \
          && ([ ${possibleWantedDlls[0]} == "dxgi" && ${possibleWantedDlls[1]} == "d3d11" ] \
           || [ ${possibleWantedDlls[1]} == "dxgi" && ${possibleWantedDlls[0]} == "d3d11" ]); then

            echo "We have detected the game needs \"dxgi.dll\" or \"d3d11.dll\" as dll override. Which one do you want? Use \"dxgi.dll\" if unsure."
            checkPCGW
            [[ $(checkStdin "(dxgi/d3d11) " "^(dxgi|d3d11)$") == "dxgi" ]] && wantedDll="dxgi" || wantedDll="d3d11"

        elif [ ${#possibleWantedDlls[@]} -eq 2 ] \
          && ([ ${possibleWantedDlls[0]} == "dxgi" && ${possibleWantedDlls[1]} == "d3d12" ] \
           || [ ${possibleWantedDlls[1]} == "dxgi" && ${possibleWantedDlls[0]} == "d3d12" ]); then

            echo "We have detected the game needs \"dxgi.dll\" or \"d3d12.dll\" as dll override. Which one do you want? Use \"dxgi.dll\" if unsure."
            checkPCGW
            [[ $(checkStdin "(dxgi/d3d12) " "^(dxgi|d3d12)$") == "dxgi" ]] && wantedDll="dxgi" || wantedDll="d3d12"

        else
            echo "We found the following possible dll overrides:"
            for possibleDll in ${possibleWantedDlls[@]}; do
                echo "$possibleDll"
            done
            echo "Enter the dll override the game needs. If both dxgi and d3d11 or d3d12 are present try using dxgi first."
            enterManualDllOverride
        fi
    else
        wantedDll="manual"
    fi
fi

if [[ $wantedDll == "manual" ]]; then
    echo "Manually enter the dll override for ReShade, common values are one of: $COMMON_OVERRIDES"
    enterManualDllOverride
fi

#EXECUTION ORDER MATTERS!
#dll override needs to be added before protontricks is called

checkUserReg "Add $wantedDll and make sure it is set to \"native,builtin\"."

addDllOverride "$wantedDll"

if [[ $D3DCOMPILER -eq 1 ]]; then
    echo -e "$SEPERATOR\nInstalling d3dcompiler_47 using protontricks."
    $PROTONTRICKS $SteamID d3dcompiler_47
fi

echo "$SEPERATOR"
if [[ $exeArch -eq 64 ]]; then
    echo "Linking ReShade64.dll as $wantedDll.dll."
    ln -is "$(realpath "$RESHADE_PATH"/ReShade64.dll)" "$gamePath/$wantedDll.dll"
else
    echo "Linking ReShade32.dll as $wantedDll.dll."
    ln -is "$(realpath "$RESHADE_PATH"/ReShade32.dll)" "$gamePath/$wantedDll.dll"
fi

setupReShadeFiles

echo -e "$SEPERATOR\nDone."
