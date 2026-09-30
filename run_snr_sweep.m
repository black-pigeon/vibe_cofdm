function rows = run_snr_sweep(snrDb,nFrames,outPath)
% Monte Carlo end-to-end PER including synchronization/header failures.
% Defaults are a SMALL smoke sweep; use >=1000 frames for characterization.
if nargin<1, snrDb=[4 8 12 16]; end
if nargin<2, nFrames=10; end
if nargin<3, outPath=''; end
assert(nFrames>=1 && nFrames==floor(nFrames));
root=fileparts(mfilename('fullpath')); addpath(root);
c=cofdm.config(); code=cofdm.ldpc_code(); cofdm.seed_rng(c.seed);
rows=zeros(numel(snrDb),8);
for s=1:numel(snrDb)
    bad=0; syncBad=0; headerBad=0; decodedBits=0; bitErrors=0;
    iterSum=0; iterCount=0;
    for f=1:nFrames
        payload=uint8(randi([0 255],c.payloadBytes,1));
        wave=cofdm.tx(payload,mod(f,65536),c,code);
        p=struct('snrDb',snrDb(s),'cfoHz',135e3,'offset',37, ...
            'delays',[0 3 9],'gains',[1 0.25*exp(0.6j) 0.12*exp(-1j)]);
        y=cofdm.channel(wave,c,p); r=cofdm.rx(y,c,code);
        bad=bad+(~r.ok || ~isequal(r.payload,payload));
        syncBad=syncBad+~r.sync.ok;
        headerBad=headerBad+(r.sync.ok && isempty(r.payload));
        if ~isempty(r.payload)
            bitErrors=bitErrors+sum(cofdm.bytes_to_bits(payload)~=cofdm.bytes_to_bits(r.payload));
            decodedBits=decodedBits+8*numel(payload);
            iterSum=iterSum+sum(r.iterations); iterCount=iterCount+numel(r.iterations);
        end
    end
    % BER is CONDITIONAL on payload being decoded; PER includes ALL failures.
    ber=NaN; if decodedBits>0, ber=bitErrors/decodedBits; end
    mi=NaN; if iterCount>0, mi=iterSum/iterCount; end
    rows(s,:)=[snrDb(s),nFrames,bad/nFrames,syncBad/nFrames,headerBad/nFrames, ...
        ber,mi,c.netRate*(1-bad/nFrames)/1e6];
    fprintf('SNR %.1f dB PER %.3f sync_fail %.3f header_fail %.3f goodput %.3f Mbps\n', ...
        rows(s,1),rows(s,3),rows(s,4),rows(s,5),rows(s,8));
end
if ~isempty(outPath)
    fid=fopen(outPath,'w'); assert(fid>=0); cl=onCleanup(@()fclose(fid));
    fprintf(fid,'sample_snr_db,frames,per,sync_fail_rate,header_fail_rate,conditional_payload_ber,mean_iterations,goodput_mbps\n');
    fprintf(fid,'%.8g,%d,%.8g,%.8g,%.8g,%.8g,%.8g,%.8g\n',rows.');
end
end
