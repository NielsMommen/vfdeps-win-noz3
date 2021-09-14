param (
  [Parameter(Mandatory)]
  [ValidateNotNullOrEmpty()]
  [string]
  $vfdeps_dir,
  [string]
  $msvc_install_dir="C:\vfMinVS",
  [ValidateSet("Debug", "MinSizeRel", "Release", "RelWithDebInfo")]
  [string]
  $build_type="Debug"
)

function createDirIfNotExists {
  param (
    [String]$path
  )
  if (! (Test-Path $path)) {
    New-Item $path -Type Directory
  }
}
function logCopyFile {
  param (
    [String]$name,
    [String]$type
  )
  Write-Host "Copied $type file $name.$type" -ForegroundColor Yellow
}

# ---- llvm + clang ----
Invoke-Expression "git clone --depth 1 --branch llvmorg-11.1.0 https://github.com/llvm/llvm-project"

# set msvc environment variables
Push-Location "$msvc_install_dir\VC\Auxiliary\Build"
Write-Output "Setting MSVC variables:"
cmd /c "vcvarsall.bat x86&set " |
ForEach-Object {
  if ($_ -match "=") {
    $v = $_.split("="); set-item -force -path "ENV:\$($v[0])"  -value "$($v[1])"; Write-Output ("  {0}:{1}" -f $v[0], $v[1])
  }
}
Pop-Location
Write-Host "`nVisual Studio 2019 Command Prompt variables set." -ForegroundColor Yellow

# build llvm + clang
Push-Location "llvm-project"
createDirIfNotExists build
Set-Location "build"
Invoke-Expression "cmake -DLLVM_ENABLE_PROJECTS=clang -DLLVM_TARGETS_TO_BUILD=X86 -DLLVM_BUILD_TOOLS=OFF -G ""Visual Studio 16 2019"" -A Win32 -Thost=x64 ..\llvm"
Invoke-Expression "msbuild ""tools\clang\clang-libraries.vcxproj"" -p:Configuration=$build_type -p:Platform=Win32"
Pop-Location

# copy cmake files to vfdeps (especially llvm-config.cmake is important)
$llvm_build_dir = "llvm-project\build"
$llvm_vfdeps_dir = "$vfdeps_dir\$llvm_build_dir"
Copy-Item -Path "$llvm_build_dir\lib\cmake\" -Destination "$llvm_vfdeps_dir\lib\cmake" -Recurse

$llvm_vfdeps_lib_dir = "$llvm_vfdeps_dir\$build_type\lib"
createDirIfNotExists $llvm_vfdeps_lib_dir

# copy clang lib files to vfdeps/lib
"Basic", "AST", "Frontend", "Tooling" | ForEach-Object {
  $lib = $_
  Copy-Item -Path "$llvm_build_dir\$build_type\lib\clang$lib.lib" -Destination $llvm_vfdeps_lib_dir
  logCopyFile "clang$lib" "lib"
}

# copy llvm lib files to vfdeps/lib
Copy-Item -Path "$llvm_build_dir\$build_type\lib\LLVMSupport.lib" -Destination $llvm_vfdeps_lib_dir
logCopyFile "LLVMSupport" "lib"

# ---- cap'n proto ----
Invoke-Expression "git clone --depth 1 --branch v0.9.0 https://github.com/capnproto/capnproto"

Push-Location "capnproto/c++"
createDirIfNotExists "build"
Set-Location "build"
Invoke-Expression "cmake -G ""Visual Studio 16 2019"" -A Win32 -Thost=x64 .."
Invoke-Expression "msbuild ""Cap'n Proto.sln"" -p:Configuration=$build_type -p:Platform=Win32"
Pop-Location

$vfdeps_lib_dir = "$vfdeps_dir\lib"
$vfdeps_bin_dir = "$vfdeps_dir\bin"
$kj_vfdeps_incl_dir = "$vfdeps_dir\include\kj"
$capnp_vfdeps_incl_dir = "$vfdeps_dir\include\capnp"

$vfdeps_lib_dir, $vfdeps_bin_dir, $kj_vfdeps_incl_dir, $capnp_vfdeps_incl_dir | ForEach-Object {
  createDirIfNotExists $_
}

$capnp_kj_build_src_dir = "capnproto\c++\build\src"

# copy capnp and kj lib/include files to vfdeps
"capnp", "kj" | ForEach-Object {
  $name = $_
  Copy-Item -Path "$capnp_kj_build_src_dir\$name\$build_type\$name.lib" -Destination $vfdeps_lib_dir
  logCopyFile $name "lib"
  Copy-Item -Path "capnproto\c++\src\$name\*.h", "capnproto\c++\src\$name\*.capnp" -Destination "$vfdeps_dir\include\$name\"
}

# copy capnp exe files to vfdeps/bin
"", "c-c++", "c-capnp" | ForEach-Object {
  $suf = $_ 
  Copy-Item -Path "$capnp_kj_build_src_dir\capnp\$build_type\capnp$suf.exe" -Destination $vfdeps_bin_dir
  logCopyFile "capnp$suf" "exe"
}