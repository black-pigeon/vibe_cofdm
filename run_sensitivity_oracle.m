function results = run_sensitivity_oracle(snrDb,nFrames,outPath)
% Diagnostic ONLY: perfect timing/CFO/channel/noise and known payload length.
% Bypasses all acquisition and header costs; not an implementable receiver.
if nargin<1, snrDb=[1 2 3 4]; end
if nargin<2, nFrames=40; end
if nargin<3, outPath=''; end
root=fileparts(mfilename('fullpath')); addpath(root);
c=cofdm.config_v2('compact'); code=cofdm.ldpc_code(); length=1500;
results=table(); seed=202609283;
for j=1:numel(snrDb)
    cofdm.seed_rng(seed+100*j); fullErrors=0; idealErrors=0;
    for k=1:nFrames
        payload=uint8(randi([0 255],length,1)); [wave,meta]=cofdm.tx(payload,0,c,code);
        p=struct('snrDb',snrDb(j),'cfoHz',0,'offset',randi([0 128]), ...
            'delays',0,'gains',exp(2j*pi*rand));
        [y,truth]=cofdm.channel(wave,c,p);
        r=cofdm.rx(y,c,code);
        fullErrors=fullErrors+(~r.ok || ~isequal(payload,r.payload));
        % Receiver truth is used only below in the explicit genie diagnostic.
        cc=meta.config; span=cc.nfft+cc.ncp;
        corrected=y.*exp(-2j*pi*p.cfoHz*(0:numel(y)-1).'/cc.fs);
        h=fft(truth.h,cc.nfft)*cc.txScale; h=h(:); hd=h(cc.dataBins);
        pos=truth.frameStart+cc.stfPeriod*cc.stfRepeats+cc.ncp+(2+cc.nHeaderSymbols)*span;
        llr=zeros(cc.bitsPerSymbol,cc.nDataSymbols);
        for s=1:cc.nDataSymbols
            f=fft(corrected(pos:pos+cc.nfft-1))/sqrt(cc.nfft); pos=pos+span;
            matched=conj(hd).*f(cc.dataBins); z=zeros(cc.bitsPerSymbol,1);
            z(1:2:end)=2*sqrt(2)*real(matched)/max(truth.noiseVariance,1e-12);
            z(2:2:end)=2*sqrt(2)*imag(matched)/max(truth.noiseVariance,1e-12);
            llr(cc.interleaver,s)=z;
            if mod(s,cc.midambleEvery)==0 && s<cc.nDataSymbols, pos=pos+span; end
        end
        llr=llr(:); blocks=reshape(llr(1:cc.nCodewords*code.n),code.n,[]);
        decoded=false(code.k,cc.nCodewords); syndrome=true;
        for s=1:cc.nCodewords
            [decoded(:,s),ok]=cofdm.ldpc_decode(blocks(:,s),code,cc);
            syndrome=syndrome && ok;
        end
        b=xor(decoded(:),cofdm.prbs(numel(decoded),cc.scramblerSeed));
        used=8*length+32;
        idealOk=syndrome && ~any(b(used+1:end)) && cofdm.crc(b(1:used),32,true) ...
            && isequal(cofdm.bits_to_bytes(b(1:8*length)),payload);
        idealErrors=idealErrors+~idealOk;
    end
    [lo,hi,upper]=cofdm.binomial_interval(idealErrors,nFrames);
    row=table(snrDb(j),nFrames,fullErrors,idealErrors,fullErrors/nFrames,idealErrors/nFrames,lo,hi,upper, ...
        'VariableNames',{'sample_snr_db','frames','full_errors','oracle_payload_errors', ...
        'full_per','oracle_per','oracle_ci95_low','oracle_ci95_high','oracle_upper95'});
    if isempty(results), results=row; else, results=[results;row]; end %#ok<AGROW>
    fprintf('AWGN oracle SNR=%g full=%d/%d oracle_payload=%d/%d\n',snrDb(j),fullErrors,nFrames,idealErrors,nFrames);
    if ~isempty(outPath), writetable(results,outPath); end
end
if ~isempty(outPath)
    manifest=struct('complete',true,'seed',seed,'seedRule','seed + 100*snrIndex', ...
        'matlabVersion',version,'snrDb',snrDb,'framesPerPoint',nFrames, ...
        'payloadBytes',length,'config',c,'channel','flat AWGN, random phase, offset 0..128, CFO=0', ...
        'oracle','perfect timing, CFO, channel, noise variance, length; header bypassed');
    fid=fopen([outPath '.json'],'w'); assert(fid>=0); cleanup=onCleanup(@()fclose(fid));
    fprintf(fid,'%s\n',jsonencode(manifest));
end
end
