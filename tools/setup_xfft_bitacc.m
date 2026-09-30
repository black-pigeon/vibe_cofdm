function info=setup_xfft_bitacc(zipFile)
%SETUP_XFFT_BITACC Extract and compile Vivado's XFFT bit-accurate MEX model.
% The generated XFFT C model is delivered by Vivado with the IP. This helper
% keeps those files outside the source tree and only builds a local MEX.
if nargin<1 || isempty(zipFile)
    matlabRoot=fileparts(fileparts(mfilename('fullpath')));
    zipFile=fullfile(matlabRoot,'vivado','cofdm_fft_ref','project',...
        'cofdm_fft_ref.gen','sources_1','ip','cofdm_fft_256','cmodel',...
        'xfft_v9_1_bitacc_cmodel_lin64.zip');
end
assert(exist(zipFile,'file')==2,'XFFT C-model zip not found: %s',zipFile);
cacheDir=fullfile(fileparts(mfilename('fullpath')),'xfft_bitacc_lin64');
if exist(cacheDir,'dir')~=7, mkdir(cacheDir); end
if exist(fullfile(cacheDir,'xfft_v9_1_bitacc_mex.mexa64'),'file')~=3 || ...
        ~strcmp(getenv('COFDM_XFFT_MEX_RPATH'),'1')
    unzip(zipFile,cacheDir);
    % The archive carries libgmp.so.11 without the linker-name symlink.
    if exist(fullfile(cacheDir,'libgmp.so.11'),'file')==2 && ...
            exist(fullfile(cacheDir,'libgmp.so'),'file')~=2
        copyfile(fullfile(cacheDir,'libgmp.so.11'),fullfile(cacheDir,'libgmp.so'));
    end
    old=pwd; cd(cacheDir);
    c=mex('-DLIN64','-DUNIX','-DNDEBUG','-D_USRDLL','-O',...
        'xfft_v9_1_bitacc_mex.cpp','-L.','-lIp_xfft_v9_1_bitacc_cmodel','-lgmp',...
        ['LDFLAGS=$LDFLAGS -Wl,-rpath,' cacheDir,',--disable-new-dtags']);
    cd(old);
    if c~=0, error('XFFT MEX build failed'); end
    setenv('COFDM_XFFT_MEX_RPATH','1');
end
addpath(cacheDir);
oldld=getenv('LD_LIBRARY_PATH');
if isempty(oldld), setenv('LD_LIBRARY_PATH',cacheDir);
elseif isempty(strfind([pathsep oldld pathsep],[pathsep cacheDir pathsep]))
    setenv('LD_LIBRARY_PATH',[cacheDir pathsep oldld]);
end
info=struct('directory',cacheDir,'mex',which('xfft_v9_1_bitacc_mex'),...
    'zip',zipFile);
fprintf('XFFT bit-accurate model ready: %s\n',info.mex);
end
