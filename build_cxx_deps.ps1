param (
  [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$vfdeps_dir,
  [string]$msvc_install_dir="C:\vfMinVS",
  [ValidateSet("Debug", "MinSizeRel", "Release", "RelWithDebInfo")][string]$build_type="Debug",
  [switch]$min_size = $false # this will only retain the minimum required llvm/clang/capnp files and remove everything else
)

function createDirIfNotExists {
  param (
    [String]$path
  )
  if (! (Test-Path $path)) {
    New-Item $path -Type Directory
  }
}
function logMoveFile {
  param (
    [String]$name,
    [String]$type
  )
  Write-Host "Moved $type file $name.$type" -ForegroundColor Yellow
}

function removeDir {
  param(
    [String]$dir
  )
  Get-ChildItem -Path $dir -Recurse | Remove-Item -Force -Recurse
  Remove-Item $dir -Force
}

# ---- llvm + clang ----

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
## We go to the vfdeps dir to make sure that the cmake configuration variables point to the correct locations
Push-Location $vfdeps_dir
Invoke-Expression "git clone --depth 1 --branch llvmorg-11.1.0 https://github.com/llvm/llvm-project"
Pop-Location

$llvm_proj_dir = "$vfdeps_dir\llvm-project"
$llvm_build_dir = "$llvm_proj_dir\build"
createDirIfNotExists $llvm_build_dir
Push-Location $llvm_build_dir
Invoke-Expression "cmake -DLLVM_ENABLE_PROJECTS=clang -DLLVM_TARGETS_TO_BUILD=X86 -DLLVM_BUILD_TOOLS=OFF -G ""Visual Studio 16 2019"" -A Win32 -Thost=x64 ../llvm"
Invoke-Expression "msbuild ""tools\clang\clang-libraries.vcxproj"" -p:Configuration=$build_type -p:Platform=Win32"
Pop-Location

if ($min_size -eq $true) {
  ## Rename the llvm proj dir and move everything we need to a fresh llvm proj dir
  $llvm_proj_dir_old = "$vfdeps_dir\llvm-project_backup"
  $llvm_build_dir_old = "$llvm_proj_dir_old\build"
  Rename-Item $llvm_proj_dir $llvm_proj_dir_old
  createDirIfNotExists $llvm_proj_dir

  # move cmake files (especially llvm-config.cmake is important)
  createDirIfNotExists $llvm_build_dir\lib\cmake
  Move-Item -Path "$llvm_build_dir_old\lib\cmake\*" -Destination "$llvm_build_dir\lib\cmake"

  $llvm_lib_dir = "$llvm_build_dir\$build_type\lib"
  createDirIfNotExists $llvm_lib_dir

  function moveLibsAndIncludes() {
    param(
      [String]$proj,
      [String]$lib_pref,
      [String[]]$libs
    )
    $libs | ForEach-Object {
      Move-Item -Path "$llvm_build_dir_old\$build_type\lib\$lib_pref$_.lib" -Destination $llvm_lib_dir
      logMoveFile "$lib_prefj$_" "lib"
      $incl_suff = "$proj\include\$proj\$_"
      $incl_dest_dir = "$llvm_proj_dir\$incl_suff"
      createDirIfNotExists $incl_dest_dir
      Move-Item -Path "$llvm_proj_dir_old\$incl_suff\*" -Destination $incl_dest_dir
    }
  }

  $clang_libs = @("Basic", "AST", "Frontend", "Tooling")
  $llvm_libs = @("Support")

  # move clang lib files and include files
  moveLibsAndIncludes -proj "clang" -lib_pref "clang" -libs $clang_libs

  # move llvm lib files and include files
  moveLibsAndIncludes -proj "llvm" -lib_pref "LLVM" -libs $llvm_libs

  removeDir $llvm_proj_dir_old
}

# ---- cap'n proto ----
Invoke-Expression "git clone --depth 1 --branch v0.9.0 https://github.com/capnproto/capnproto"

Push-Location "capnproto\c++"
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
  logMoveFile $name "lib"
  Copy-Item -Path "capnproto\c++\src\$name\*.h", "capnproto\c++\src\$name\*.capnp" -Destination "$vfdeps_dir\include\$name\"
}

# copy capnp exe files to vfdeps/bin
"", "c-c++", "c-capnp" | ForEach-Object {
  $suf = $_ 
  Copy-Item -Path "$capnp_kj_build_src_dir\capnp\$build_type\capnp$suf.exe" -Destination $vfdeps_bin_dir
  logMoveFile "capnp$suf" "exe"
}

if ($min_size -eq $true) {
  removeDir "capnproto"
}