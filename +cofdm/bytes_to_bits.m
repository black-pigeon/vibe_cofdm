function b = bytes_to_bits(x)
% Network ordering: first byte first, MSB first within each byte.
x=uint8(x(:)); b=false(8*numel(x),1);
for k=1:8, b(k:8:end)=logical(bitget(x,9-k)); end
end
