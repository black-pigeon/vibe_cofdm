function out = crc(bits,width,check)
% Non-reflected polynomial division, zero initial state, zero final XOR.
% These conventions are part of OUR frame format (not Ethernet CRC-32).
if nargin<3, check=false; end
if width==16
    poly=uint32(hex2dec('1021'));
elseif width==32
    poly=uint32(hex2dec('04C11DB7'));
else
    error('Unsupported CRC width');
end
g=[true; logical(bitget(poly,width:-1:1)).'];
bits=logical(bits(:));
if check, work=bits; n=numel(bits)-width;
else, work=[bits;false(width,1)]; n=numel(bits); end
for k=1:n
    if work(k), work(k:k+width)=xor(work(k:k+width),g); end
end
if check, out=~any(work(end-width+1:end));
else, out=[bits;work(end-width+1:end)]; end
end
