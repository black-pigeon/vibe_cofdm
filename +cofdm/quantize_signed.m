function [y,saturations] = quantize_signed(x,bits,fraction)
% Signed two's-complement range; nearest rounding, ties away from zero.
% Complex components are rounded/saturated separately. Double integer
% arithmetic is exact only while intermediates stay within 2^53.
assert(bits>=2 && bits<=32 && bits==floor(bits));
assert(fraction>=0 && fraction<bits && fraction==floor(fraction));
assert(all(isfinite(x(:))),'Non-finite fixed-point input');
scale=2^fraction; lo=-2^(bits-1); hi=2^(bits-1)-1;
r=round(real(x)*scale);
saturations=sum(r(:)<lo | r(:)>hi);
y=max(lo,min(hi,r))/scale;
if ~isreal(x)
    im=round(imag(x)*scale);
    saturations=saturations+sum(im(:)<lo | im(:)>hi);
    y=complex(y,max(lo,min(hi,im))/scale);
end
end
