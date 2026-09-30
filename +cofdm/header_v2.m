function out = header_v2(action,value,c)
% Header bits MSB first: version4, mcs4, length12, seed7, mid2, reserved3.
switch action
    case 'encode'
        c=cofdm.frame_layout(c,value);
        fields=[c.version c.profile c.payloadBytes c.scramblerSeed c.midambleCode 0];
        widths=[4 4 12 7 2 3]; bits=false(0,1);
        for k=1:numel(fields)
            bits=[bits;logical(bitget(uint32(fields(k)),widths(k):-1:1)).']; %#ok<AGROW>
        end
        coded=cofdm.header_conv_encode(cofdm.crc(bits,16));
        pad=false(numel(c.data)-numel(coded),1);
        out=xor([coded;pad],cofdm.prbs(numel(c.data),c.headerScramblerSeed));
    case 'decode'
        out=struct('ok',false,'reason','header Viterbi/CRC failure');
        if numel(value)~=numel(c.data) || any(~isfinite(value)), return; end
        llr=value(:).*(1-2*double(cofdm.prbs(numel(c.data),c.headerScramblerSeed)));
        [bits,ok]=cofdm.header_viterbi(llr(1:108));
        if ~ok || ~cofdm.crc(bits,16,true), return; end
        widths=[4 4 12 7 2 3]; fields=zeros(1,6); pos=1;
        for k=1:numel(widths)
            fields(k)=double(bits(pos:pos+widths(k)-1)).'*(2.^(widths(k)-1:-1:0)).';
            pos=pos+widths(k);
        end
        if fields(1)~=2 || fields(2)~=0 || fields(3)<1 || ...
                fields(3)>min(c.maxPayloadBytes,2048) || fields(4)==0 || fields(5)>2 || fields(6)~=0
            out.reason='unsupported v2 version/MCS/length/seed/mid/reserved'; return;
        end
        c.profile=fields(2); c.scramblerSeed=fields(4); c.midambleCode=fields(5);
        out.config=cofdm.frame_layout(c,fields(3)); out.ok=true; out.reason='';
    otherwise
        error('Unknown v2 header action');
end
end
