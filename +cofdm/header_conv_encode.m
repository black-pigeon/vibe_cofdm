function coded = header_conv_encode(bits)
% Zero initial state; append six zero tail bits to terminate in state zero.
t=cofdm.header_trellis(); input=[logical(bits(:));false(6,1)];
state=0; coded=false(2*numel(input),1);
for k=1:numel(input)
    coded(2*k-1:2*k)=reshape(t.output(state+1,double(input(k))+1,:),2,1);
    state=t.next(state+1,double(input(k))+1);
end
assert(state==0);
end
