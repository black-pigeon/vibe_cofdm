function results=run_full_link_ldpc_comparison(lengths,snrs,nFrames,outPath)
% Paired complete MATLAB PHY RX; no timing/CFO/channel truth enters RX.
% Same post-frontend LLRs are decoded by each candidate. Quantized NMS uses
% Q2 +/-63 input/messages and +/-255 posterior, matching scalar RTL units.
if nargin<1,lengths=[36 257 2048];end
if nargin<2,snrs=[4 5 6];end
if nargin<3,nFrames=100;end
if nargin<4,outPath='results/full_link_ldpc.csv';end
assert(nFrames>=1 && nFrames==fix(nFrames));
root=fileparts(mfilename('fullpath'));addpath(root);
folder=fileparts(outPath);if ~isempty(folder)&&~exist(folder,'dir'),mkdir(folder);end
code=cofdm.ldpc_code();base=cofdm.config_v2('compact');
labels={'float12','q2_nms6','q2_nms12','q2_nms20','q2_alpha_half12'};
limits=[12 6 12 20 12];alphas=[.75 .75 .75 .75 .5];seed=20261002;
results=table();
manifest=struct('complete',false,'seed',seed,'lengths',lengths,'snrs',snrs,...
 'nFrames',nFrames,'labels',{labels},'limits',limits,'alphas',alphas,...
 'seedRule','seed+100000*length+1000*snr+frame; shared IQ across decoders',...
 'scope','MATLAB full synchronization/header/frontend; RTL-arithmetic payload candidates, not RTL full-chain PER',...
 'channel','static normalized [0 3 9] delays, amplitudes [1 .25 .12], random phases; +/-135kHz CFO; offset 0..128',...
 'quantization','round(4*analyticalLLR), saturate +/-63; decoder receives q/4',...
 'version',version);
write_manifest(outPath,manifest);
for L=lengths
 layout=cofdm.frame_layout(base,L);
 for snr=snrs
  counts=zeros(numel(labels),7); % errors, sync, header, payload, iterations, words, maxIt
  for frame=1:nFrames
   cofdm.seed_rng(seed+100000*L+1000*snr+frame);
   payload=uint8(randi([0 255],L,1));wave=cofdm.tx(payload,0,base,code);
   p=struct('snrDb',snr,'cfoHz',135e3*(2*randi([0 1])-1),'offset',randi([0 128]),...
     'delays',[0 3 9],'gains',[1 .25 .12].*exp(2j*pi*rand(1,3)));
   y=cofdm.channel(wave,base,p);
   frontend=base;frontend.ldpcIterations=1;
   r=cofdm.rx(y,frontend,code);
   for d=1:numel(labels)
    if ~r.sync.ok,counts(d,1:2)=counts(d,1:2)+1;continue;end
    if ~r.header.ok,counts(d,[1 3])=counts(d,[1 3])+1;continue;end
    cfg=r.frameConfig;cfg.ldpcIterations=limits(d);cfg.ldpcAlpha=alphas(d);
    cfg.quantizedDecoder=d~=1;
    llr=r.codedLLR;
    if cfg.quantizedDecoder,llr=max(-63,min(63,round(4*llr)))/4;end
    blocks=reshape(llr,648,[]);u=false(324,cfg.nCodewords);ok=true;
    for w=1:cfg.nCodewords
     [u(:,w),pass,it]=cofdm.ldpc_decode(blocks(:,w),code,cfg);ok=ok&&pass;
     counts(d,5:6)=counts(d,5:6)+[it 1];counts(d,7)=max(counts(d,7),it);
    end
    b=xor(u(:),cofdm.prbs(numel(u),cfg.scramblerSeed));used=8*L+32;
    pass=ok && ~any(b(used+1:end)) && cofdm.crc(b(1:used),32,true) && ...
       isequal(cofdm.bits_to_bytes(b(1:8*L)),payload);
    counts(d,[1 4])=counts(d,[1 4])+~pass;
   end
   if mod(frame,25)==0,fprintf('L=%d SNR=%g frame=%d/%d\n',L,snr,frame,nFrames);end
  end
  for d=1:numel(labels)
   a=counts(d,:);[lo,hi,upper]=cofdm.binomial_interval(a(1),nFrames);
   row=table(L,snr,labels(d),nFrames,a(1),a(2),a(3),a(4),a(1)/nFrames,lo,hi,upper,...
     a(5)/max(1,a(6)),a(7),layout.netRate*(1-a(1)/nFrames)/1e6,...
     'VariableNames',{'payload_bytes','snr_db','decoder','frames','errors','sync_fail','header_fail',...
     'payload_fail','per','ci95_low','ci95_high','upper95','mean_iterations','max_iterations','air_goodput_mbps'});
   results=[results;row]; %#ok<AGROW>
  end
  writetable(results,outPath);disp(results(end-4:end,{'payload_bytes','snr_db','decoder','per','mean_iterations'}));
 end
end
manifest.complete=true;write_manifest(outPath,manifest);
end
function write_manifest(path,m)
f=fopen([path '.json'],'w');assert(f>=0);cl=onCleanup(@()fclose(f));fprintf(f,'%s\n',jsonencode(m));
end
