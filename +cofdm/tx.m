function [wave,meta] = tx(payload,seq,c,code)
% Legacy fixed v1 or explicit variable-length v2; identical OFDM numerology.
payload=uint8(payload(:));
if c.variablePayload, c=cofdm.frame_layout(c,numel(payload)); end
assert(numel(payload)==c.payloadBytes);
assert(seq>=0 && seq<=65535 && seq==floor(seq));
if c.variablePayload
    assert(seq==0,'v2 PHY has no sequence field; put sequence in MAC payload');
    hmap=cofdm.header_v2('encode',numel(payload),c);
    hcw=xor(hmap,cofdm.prbs(numel(hmap),c.headerScramblerSeed)); hcw=hcw(1:108);
else
header=uint8([c.version;c.profile;floor(c.payloadBytes/256); ...
    mod(c.payloadBytes,256);floor(seq/256);mod(seq,256);c.nCodewords;0]);
hb=cofdm.crc(cofdm.bytes_to_bits(header),16);
hcw=cofdm.ldpc_encode([hb;false(code.k-numel(hb),1)],code);
hmap=[hcw;false(c.nHeaderSymbols*numel(c.data)-code.n,1)];
hmap=xor(hmap,cofdm.prbs(numel(hmap),c.headerScramblerSeed));
end
b=cofdm.crc(cofdm.bytes_to_bits(payload),32);
if c.variablePayload, b=[b;false(c.infoPadBits,1)]; end
b=xor(b,cofdm.prbs(numel(b),c.scramblerSeed));
u=reshape(b,code.k,[]); cw=false(code.n,c.nCodewords);
for k=1:c.nCodewords, cw(:,k)=cofdm.ldpc_encode(u(:,k),code); end
symbolBits=cw(:);
if c.variablePayload
    symbolBits=[symbolBits;cofdm.prbs(c.codedPadBits,c.symbolPadSeed)];
end
mapped=reshape(symbolBits,c.bitsPerSymbol,[]);
t=cofdm.training(c); wave=t.stf;
for k=1:2, wave=[wave;cofdm.ofdm_symbol(c,t.ltf(:,k))]; end %#ok<AGROW>
symbolIndex=0; meta.symbolTypes={'LTF1','LTF2'};
for k=1:c.nHeaderSymbols
    symbolIndex=symbolIndex+1; a=zeros(numel(c.active),1);
    a(c.pilotInActive)=cofdm.pilot_values(c,symbolIndex);
    a(c.dataInActive)=1-2*double(hmap((k-1)*numel(c.data)+(1:numel(c.data))));
    wave=[wave;cofdm.ofdm_symbol(c,a)]; %#ok<AGROW>
    meta.symbolTypes{end+1}='HEADER';
end
for k=1:c.nDataSymbols
    symbolIndex=symbolIndex+1; a=zeros(numel(c.active),1);
    a(c.pilotInActive)=cofdm.pilot_values(c,symbolIndex);
    bits=double(mapped(c.interleaver,k));
    a(c.dataInActive)=((1-2*bits(1:2:end))+1j*(1-2*bits(2:2:end)))/sqrt(2);
    wave=[wave;cofdm.ofdm_symbol(c,a)]; %#ok<AGROW>
    meta.symbolTypes{end+1}='DATA';
    if mod(k,c.midambleEvery)==0 && k<c.nDataSymbols
        symbolIndex=symbolIndex+1;
        wave=[wave;cofdm.ofdm_symbol(c,t.ltf(:,1))]; %#ok<AGROW>
        meta.symbolTypes{end+1}='MIDAMBLE';
    end
end
assert(numel(wave)==c.frameSamples);
meta.paprDb=10*log10(max(abs(wave).^2)/mean(abs(wave).^2));
meta.codedBits=cw(:); meta.headerBits=hcw;
meta.config=c;
wave=[wave;zeros(c.guardSamples,1)];
end
