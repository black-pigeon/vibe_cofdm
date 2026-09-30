function results = run_payload_sweep_fast(lengths,snrDb,nFrames,outPath,options)
% Fast payload-only Monte Carlo model for the v2 PHY.
%
% Timing, CFO and payload length are supplied to the receiver; channel is
% estimated from noisy LTFs. The
% waveform still passes through the same TX, multipath and AWGN functions and
% the same pilot/channel/LLR/LDPC code used by cofdm.rx; acquisition and the
% V2 header are deliberately bypassed.  Consequently this is a payload
% implementation/SNR sweep, not an end-to-end sensitivity result.  Use
% run_variable_sweep or run_sensitivity_sweep for the latter.
%
% rtl7 uses Q2 input/messages and Q2 posterior saturation of the RTL decoder.
% This models decoder arithmetic, not the fixed-point RTL frontend. Set
% options.decoderMode='float' for an algorithm ceiling comparison.
if nargin<1 || isempty(lengths), lengths=[1 36 257 1024 2048]; end
if nargin<2 || isempty(snrDb), snrDb=0:2:12; end
if nargin<3 || isempty(nFrames), nFrames=10; end
if nargin<4, outPath=''; end
if nargin<5, options=struct(); end
root=fileparts(mfilename('fullpath')); addpath(root);
if ~isfield(options,'seed'), options.seed=20260930; end
if ~isfield(options,'decoderMode'), options.decoderMode='rtl7'; end
if ~isfield(options,'receiverMode'), options.receiverMode='compact'; end
if ~isfield(options,'cfoHz'), options.cfoHz=135e3; end
if ~isfield(options,'delays'), options.delays=[0 3 9]; end
if ~isfield(options,'amplitudes'), options.amplitudes=[1 .25 .12]; end
if ~isfield(options,'ldpcIterations'), options.ldpcIterations=12; end
assert(any(strcmp(options.decoderMode,{'rtl7','float'})));
assert(nFrames>=1 && nFrames==floor(nFrames));
base=cofdm.config_v2(options.receiverMode); code=cofdm.ldpc_code();
base.ldpcIterations=options.ldpcIterations;
names={'channel','decoder_mode','payload_bytes','sample_snr_db','frames',...
    'packet_errors','ldpc_failures','crc_failures','per','ci95_low','ci95_high','upper95',...
    'codewords','data_symbols','slot_us','ideal_goodput_mbps','goodput_mbps','mean_iterations',...
    'max_iterations','scalar_ldpc_cycles','scalar_ldpc_service_us','scalar_service_goodput_mbps',...
    'required_parallel_lanes','worst_case_parallel_lanes'};
rows=cell(0,numel(names));
for il=1:numel(lengths)
    L=lengths(il); c=cofdm.frame_layout(base,L); span=c.nfft+c.ncp;
    for is=1:numel(snrDb)
        cofdm.seed_rng(options.seed+10000*il+100*is);
        bad=0; ldpcBad=0; crcBad=0; itSum=0; itMax=0; itCount=0;
        for frame=1:nFrames
            payload=uint8(randi([0 255],L,1));
            [wave,~]=cofdm.tx(payload,0,base,code);
            gains=options.amplitudes.*exp(2j*pi*rand(size(options.amplitudes)));
            p=struct('snrDb',snrDb(is),'cfoHz',options.cfoHz,'offset',37,...
                'delays',options.delays,'gains',gains);
            [y,truth]=cofdm.channel(wave,base,p);
            [llr,cw,cfg]=payload_llr_known_capture(y,p,truth,c,code);
            if strcmp(options.decoderMode,'rtl7')
                llr=max(-63,min(63,round(4*llr)))/4;
                c.quantizedDecoder=true;
            end
            blocks=reshape(llr(1:c.nCodewords*code.n),code.n,[]);
            u=false(code.k,c.nCodewords); oks=false(c.nCodewords,1); its=zeros(c.nCodewords,1);
            for w=1:c.nCodewords
                [u(:,w),oks(w),its(w)]=cofdm.ldpc_decode(blocks(:,w),code,c);
            end
            b=xor(u(:),cofdm.prbs(numel(u),c.scramblerSeed)); used=8*L+32;
            paddingOk=~any(b(used+1:end)); crcOk=cofdm.crc(b(1:used),32,true);
            decoded=cofdm.bits_to_bytes(b(1:8*L)); ok=all(oks)&&paddingOk&&crcOk&&isequal(decoded,payload);
            bad=bad+~ok; ldpcBad=ldpcBad+~all(oks); crcBad=crcBad+~crcOk;
            itSum=itSum+sum(its); itMax=max(itMax,max(its)); itCount=itCount+numel(its);
        end
        [lo,hi,upper]=cofdm.binomial_interval(bad,nFrames);
        mi=itSum/max(itCount,1); slotUs=c.slotSamples/base.fs*1e6;
        ideal=c.netRate/1e6; goodput=ideal*(1-bad/nFrames);
        arrivalCycles=(code.n/c.bitsPerSymbol)*span*8; % 122.88 MHz / 15.36 MHz = 8
        scalarCycles=23008*mi; serviceUs=scalarCycles/122.88; % calibrated RTL scalar baseline
        serviceGoodput=(8*L*nFrames)/(max(c.slotSamples*8*nFrames,scalarCycles*c.nCodewords*nFrames))*122.88;
        lanes=ceil(scalarCycles/max(arrivalCycles,1));
        % Measured scalar RTL worst case includes fixed setup/syndrome overhead.
        % It is 258550 cycles for the configured 12-iteration decoder, rather
        % than exactly 12*23008.
        worst=ceil(258550/max(arrivalCycles,1));
        row={"short_multipath",options.decoderMode,L,snrDb(is),nFrames,bad,ldpcBad,crcBad,bad/nFrames,lo,hi,upper,...
            c.nCodewords,c.nDataSymbols,slotUs,ideal,goodput,mi,itMax,scalarCycles,serviceUs,serviceGoodput,lanes,worst};
        rows(end+1,:)=row; %#ok<AGROW>
        % Persist after every SNR/length point so a long Monte Carlo run can
        % be resumed or inspected even if MATLAB is interrupted.
        if ~isempty(outPath)
            writetable(cell2table(rows,'VariableNames',names),outPath);
        end
        fprintf('%s L=%d SNR=%g PER=%d/%d meanIt=%.2f ideal=%.3f Mbps lanes=%d\n',...
            options.decoderMode,L,snrDb(is),bad,nFrames,mi,ideal,lanes);
    end
end
results=cell2table(rows,'VariableNames',names);
if ~isempty(outPath)
    writetable(results,outPath);
    manifest=struct('complete',true,'matlabVersion',version,'seed',options.seed,...
        'lengths',lengths,'snrDb',snrDb,'framesPerPoint',nFrames,'receiverMode',options.receiverMode,...
        'decoderMode',options.decoderMode,'channel','static multipath; known timing/CFO; noisy LTF channel estimate',...
        'sampleSnrDefinition','complex active-frame sample SNR; noise bandwidth Fs',...
        'scope','payload-only oracle; acquisition and V2 header bypassed',...
        'modelRevision','Q2-input-message-posterior-v2',...
        'quantization','rtl7: round(4*LLR), saturate +/-63, decode q/4 with quantizedDecoder=true',...
        'rtlCycleCalibration','23008*meanIt approximate only; 258550 cycles at 12 iterations; 122.88 MHz');
    fid=fopen([outPath '.json'],'w'); assert(fid>=0); cl=onCleanup(@()fclose(fid));
    fprintf(fid,'%s\n',jsonencode(manifest));
end
end

function [llr,cw,c]=payload_llr_known_capture(y,p,truth,c,code)
% Reproduce cofdm.rx after its synchronize() result is known.
t=cofdm.training(c); span=c.nfft+c.ncp; frameStart=p.offset+1;
first=frameStart+numel(t.stf)+c.ncp; n=(0:numel(y)-1).';
v=y.*exp(-1j*2*pi*p.cfoHz*n/c.fs);
Y1=fft(v(first:first+c.nfft-1))/sqrt(c.nfft);
Y2=fft(v(first+span:first+span+c.nfft-1))/sqrt(c.nfft);
H1=Y1(c.activeBins)./t.ltf(:,1); H2=Y2(c.activeBins)./t.ltf(:,2);
nv=max(mean(abs(H1-H2).^2)/2,1e-9);
[H,channelVariance]=cofdm.estimate_channel((H1+H2)/2,nv/2,c);
pos=first+2*span; symbolIndex=0; pilotState=[];
% Header symbol is consumed using the same channel/tracker path, but its
% decoded fields are known to this oracle.
for k=1:c.nHeaderSymbols
    symbolIndex=symbolIndex+1; Y=fft(v(pos:pos+c.nfft-1))/sqrt(c.nfft); Y=Y(c.activeBins); pos=pos+span;
    [~,~,~,pilotState]=cofdm.track_pilots(Y,H,nv,channelVariance,c,symbolIndex,pilotState);
end
llr=zeros(c.bitsPerSymbol,c.nDataSymbols); cw=[];
for k=1:c.nDataSymbols
    symbolIndex=symbolIndex+1; Y=fft(v(pos:pos+c.nfft-1))/sqrt(c.nfft); Y=Y(c.activeBins); pos=pos+span;
    [Y,~,~,pilotState]=cofdm.track_pilots(Y,H,nv,channelVariance,c,symbolIndex,pilotState);
    hd=H(c.dataInActive); yd=Y(c.dataInActive); matched=conj(hd).*yd;
    en=nv+c.channelErrorAwareLLR*channelVariance(c.dataInActive);
    z=zeros(c.bitsPerSymbol,1); z(1:2:end)=c.llrScale*2*sqrt(2)*real(matched)./en;
    z(2:2:end)=c.llrScale*2*sqrt(2)*imag(matched)./en; llr(c.interleaver,k)=z;
    if mod(k,c.midambleEvery)==0 && k<c.nDataSymbols
        symbolIndex=symbolIndex+1; raw=fft(v(pos:pos+c.nfft-1))/sqrt(c.nfft); pos=pos+span;
        raw=raw(c.activeBins)./t.ltf(:,1); [fresh,freshVar]=cofdm.estimate_channel(raw,nv,c);
        if c.channelFusion, [H,channelVariance]=cofdm.fuse_channel(H,channelVariance,fresh,freshVar,c,c.pilotInActive);
        else, H=fresh; channelVariance=freshVar; end
    end
end
llr=llr(:); cw=c.nCodewords;
end
