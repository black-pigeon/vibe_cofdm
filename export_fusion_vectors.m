function export_fusion_vectors(outDir)
% Deterministic integer vectors for the MID fusion RTL controller.
root=fileparts(mfilename('fullpath')); if nargin<1, outDir=fullfile(root,'vectors','fusion_ctrl'); end
if ~exist(outDir,'dir'), mkdir(outDir); end
active=[-100:-1 1:100].'; pilots=[-91 -65 -39 -13 13 39 65 91].';
pilotMask=ismember(active,pilots); N=numel(active); W=18; F=2;
cases=struct('name',{'q0_slow','q1_slow','q2_fast','q3_slow'}, ...
    'rot', {0,1,2,3}, 'fast', {false,false,true,false}, ...
    'variance',{10000,10000,100,10000});
for n=1:numel(cases)
    k=(0:N-1).'; old=int32(mod(7000+113*k,18000)-9000);
    oi=int32(mod(3000+71*k,8000)-4000);
    oldc=double(old)+1j*double(oi);
    switch cases(n).rot
        case 0, freshc=oldc+(2+1j*mod(k,3));
        case 1, freshc=-1j*oldc+(1-1j*mod(k,2));
        case 2, freshc=-oldc+(3+1j*mod(k,2));
        otherwise, freshc=1j*oldc+(2-1j*mod(k,3));
    end
    if cases(n).fast, freshc=1.35*freshc; end
    fr=int32(round(real(freshc))); fi=int32(round(imag(freshc)));
    % Force a few extreme values to exercise signed arithmetic, not saturation.
    if n==4, fr(17)=int32(-12000); fi(17)=int32(11000); end
    ov=uint32(cases(n).variance*ones(N,1)); fv=uint32(cases(n).variance*ones(N,1));
    oldd=double(old)+1j*double(oi); freshd=double(fr)+1j*double(fi);
    cross=sum(freshd(pilotMask).*conj(oldd(pilotMask)));
    if abs(real(cross))>=abs(imag(cross)), rot=double(real(cross)<0)*2;
    elseif imag(cross)>=0, rot=1; else, rot=3; end
    diff=freshd(pilotMask)-oldd(pilotMask);
    innovation=sum(abs(diff).^2); variance=sum(double(ov(pilotMask))+double(fv(pilotMask)));
    fast=innovation>4*variance; alpha=1; if ~fast, alpha=1/4; end
    aligned=freshd; switch rot, case 1, aligned=-1j*freshd; case 2, aligned=-freshd; case 3, aligned=1j*freshd; end
    next=oldd+alpha*(aligned-oldd);
    % RTL arithmetic shift is floor division for negative values.
    if ~fast, nr=floor(real(next)); ni=floor(imag(next)); else, nr=real(next); ni=imag(next); end
    nr=max(-131072,min(131071,round(nr))); ni=max(-131072,min(131071,round(ni)));
    input=[(0:N-1).' double(pilotMask) double(old) double(oi) double(fr) double(fi) double(ov) double(fv)];
    expected=[(0:N-1).' nr(:) ni(:)];
    write_csv(fullfile(outDir,sprintf('case_%d_input.csv',n-1)), ...
        'index,pilot,old_re,old_im,fresh_re,fresh_im,old_var,fresh_var',input);
    write_csv(fullfile(outDir,sprintf('case_%d_expected.csv',n-1)), ...
        'index,next_re,next_im',expected);
    manifest(n)=struct('name',cases(n).name,'rotation',rot,'fast',fast, ...
        'innovation',innovation,'variance',variance,'alpha',alpha,'width',W, ...
        'fuseShift',F,'activeCarriers',active,'pilotCarriers',pilots); %#ok<AGROW>
end
fid=fopen(fullfile(outDir,'manifest.json'),'w'); assert(fid>=0); cleanup=onCleanup(@()fclose(fid));
fprintf(fid,'%s\n',jsonencode(struct('complete',true,'cases',manifest, ...
    'integerRule','pilot correlation uses full products; slow update uses arithmetic floor right shift; saturate to signed W bits')));
fprintf('Exported fusion controller vectors to %s\n',outDir);
end
function write_csv(path,header,values)
fid=fopen(path,'w'); assert(fid>=0); cleanup=onCleanup(@()fclose(fid)); fprintf(fid,'%s\n',header);
format=[repmat('%d,',1,size(values,2)-1) '%d\n']; fprintf(fid,format,values.');
end
