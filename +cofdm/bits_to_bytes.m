function x = bits_to_bytes(b)
assert(mod(numel(b),8)==0);
b=reshape(double(b),8,[]);
x=uint8((2.^(7:-1:0))*b).';
end
