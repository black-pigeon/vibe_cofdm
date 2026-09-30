function results=run_ldpc_family_screen(nFrames,ebn0s,outPath)
% Coding-only AWGN screen using installed R2020b WLAN Toolbox (no RTL claim).
% Internal Toolbox APIs are version-sensitive; no Toolbox source/matrix is copied.
if nargin<1,nFrames=500;end
if nargin<2,ebn0s=[1 2 3 4];end
if nargin<3,outPath='results/ldpc_family_awgn.csv';end
assert(nFrames>=1 && nFrames==fix(nFrames));
% Toolbox availability is checked by the first internal decoder call below.
folder=fileparts(outPath);if ~isempty(folder)&&~exist(folder,'dir'),mkdir(folder);end
seed=20261003; results=table();
manifest=struct('complete',false,'seed',seed,'framesPerPoint',nFrames,'ebn0',ebn0s,...
 'version',version,'scope','coding-only BPSK AWGN; floating Toolbox decoders; no PHY/RTL/resource measurement',...
 'normalization','Eb/N0 per information bit; sigma^2=1/(2*R*EbN0); coded-bit Es/N0=Eb/N0+10log10(R)',...
 'algorithms','layered NMS alpha=.75; for 648 half also layered OMS beta=.5 and layered BP; 12 iterations, early stop');
write_json(outPath,manifest);
for n=[648 1296 1944]
 for rate=[1/2 2/3 3/4]
  k=round(n*rate);cofdm.seed_rng(seed+n+k);
  u=int8(randi([0 1],k,nFrames));
  cw=[u;wlan.internal.ldpcEncodeCore(u,rate)];
  assert(isequal(size(cw),[n nFrames]));
  if n==648 && rate==.5
   code=cofdm.ldpc_code();
   assert(isequal(logical(cw(:,1)),cofdm.ldpc_encode(logical(u(:,1)),code)),...
       'Toolbox baseline matrix differs from project matrix');
  end
  [clean,~,parity]=wlan.internal.ldpcDecodeCore(20*(1-2*double(cw)),rate,2,.75,12,true);
  assert(isequal(clean,u)&&~any(parity(:)),'Noiseless coding self-check failed');
  cofdm.seed_rng(seed+10*n+k);noise=randn(n,nFrames);
  for ebn0=ebn0s
   variance=1/(2*rate*10^(ebn0/10));
   y=1-2*double(cw)+sqrt(variance)*noise;llr=2*y/variance;
   algs=2;labels={'nms075'};params=.75;
   if n==648 && rate==.5,algs=[2 3 1];labels={'nms075','oms050','layered_bp'};params=[.75 .5 0];end
   for a=1:numel(algs)
    [bits,its,parity]=wlan.internal.ldpcDecodeCore(llr,rate,algs(a),params(a),12,true);
    wrong=bits~=u; bad=sum(any(wrong,1)|any(parity,1));
    [lo,hi,upper]=cofdm.binomial_interval(bad,nFrames);
    row=table(n,k,rate,labels(a),ebn0,ebn0+10*log10(rate),nFrames,bad,bad/nFrames,...
     lo,hi,upper,sum(wrong(:))/(k*nFrames),mean(its),max(its),rate*(1-bad/nFrames),...
     'VariableNames',{'n','k','rate','decoder','ebn0_db','coded_esn0_db','frames','block_errors',...
      'bler','ci95_low','ci95_high','upper95','ber','mean_iterations','max_iterations','info_bits_per_coded_use'});
    results=[results;row]; %#ok<AGROW>
    fprintf('N=%d R=%g %s EbN0=%g BLER=%d/%d\n',n,rate,labels{a},ebn0,bad,nFrames);
   end
  end
  writetable(results,outPath);
 end
end
manifest.complete=true;write_json(outPath,manifest);
end
function write_json(path,m)
f=fopen([path '.json'],'w');assert(f>=0);cl=onCleanup(@()fclose(f));fprintf(f,'%s\n',jsonencode(m));
end
