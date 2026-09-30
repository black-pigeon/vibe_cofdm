function t = header_trellis()
% K=7, generators octal [171 133], output in that order.
% Register [newest input, previous six bits]; next state = register >> 1.
persistent cache
if isempty(cache)
    cache.next=zeros(64,2); cache.output=false(64,2,2);
    for state=0:63
        for input=0:1
            reg=uint16(64*input+state);
            cache.next(state+1,input+1)=floor(double(reg)/2);
            for k=1:2
                generators=uint16([121 91]);
                cache.output(state+1,input+1,k)=mod(sum(bitget(bitand(reg,generators(k)),1:7)),2)~=0;
            end
        end
    end
end
t=cache;
end
