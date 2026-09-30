function rows = run_variable_sweep(lengths,snrDb,nFrames,outPath)
% Small characterization of v2; includes detection and header failures.
if nargin<1, lengths=[36 644 1500]; end
if nargin<2, snrDb=[4 6 8]; end
if nargin<3, nFrames=20; end
if nargin<4, outPath=''; end
root=fileparts(mfilename('fullpath')); addpath(root);
c=cofdm.config_v2('compact'); code=cofdm.ldpc_code(); cofdm.seed_rng(20261009);
assert(nFrames>=1 && nFrames==floor(nFrames));
rows=zeros(0,11); fid=-1;
if ~isempty(outPath)
    fid=fopen(outPath,'w'); assert(fid>=0); cleanup=onCleanup(@()fclose(fid));
    fprintf(fid,'payload_bytes,sample_snr_db,frames,packet_errors,sync_failures,header_failures,payload_failures,per,slot_us,goodput_mbps,mean_payload_iterations\n');
end
for length=lengths
    layout=cofdm.frame_layout(c,length);
    for snr=snrDb
        errors=0; syncBad=0; headerBad=0; payloadBad=0; iterations=0; words=0;
        for k=1:nFrames
            payload=uint8(randi([0 255],length,1)); wave=cofdm.tx(payload,0,c,code);
            p=struct('snrDb',snr,'cfoHz',135e3,'offset',37, ...
                'delays',[0 3 9],'gains',[1 0.25*exp(0.6j) 0.12*exp(-1j)]);
            y=cofdm.channel(wave,c,p); r=cofdm.rx(y,c,code);
            failed=~r.ok || ~isequal(r.payload,payload); errors=errors+failed;
            if ~r.sync.ok
                syncBad=syncBad+1;
            elseif ~r.header.ok
                headerBad=headerBad+1;
            else
                payloadBad=payloadBad+failed;
            end
            if isfield(r,'iterations'), iterations=iterations+sum(r.iterations); words=words+numel(r.iterations); end
        end
        mi=NaN; if words>0, mi=iterations/words; end
        row=[length snr nFrames errors syncBad headerBad payloadBad errors/nFrames ...
            layout.slotSamples/c.fs*1e6 layout.netRate*(1-errors/nFrames)/1e6 mi];
        rows(end+1,:)=row; %#ok<AGROW>
        fprintf('v2 %d bytes SNR %g PER %.3f sync/header/payload %d/%d/%d\n', ...
            length,snr,row(8),syncBad,headerBad,payloadBad);
        if fid>=0, fprintf(fid,'%d,%.8g,%d,%d,%d,%d,%d,%.8g,%.8g,%.8g,%.8g\n',row); end
    end
end
end
