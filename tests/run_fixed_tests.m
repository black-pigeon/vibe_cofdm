function run_fixed_tests()
root=fileparts(fileparts(mfilename('fullpath'))); addpath(root);
c=cofdm.receiver_config(cofdm.config(),'compact_fixed'); code=cofdm.ldpc_code();
cofdm.seed_rng(20261002);
[q,s]=cofdm.quantize_signed([-9 -8 -0.125 0.125 7.875 8],6,2);
assert(isequal(q,[-8 -8 -0.25 0.25 7.75 7.75]) && s==3);
[q,s]=cofdm.quantize_signed(complex(20,-20),6,2);
assert(q==complex(7.75,-8) && s==2);
fprintf('PASS signed range, tie rounding and complex saturation\n');
% Integer reference uses direct scalar stencil / integer rounding, not conv
% or the production quantizer. Compare all carriers, DC edges included.
for amplitude=[0.001 0.25 2 20]
    raw=amplitude*(randn(numel(c.active),1)+1j*randn(numel(c.active),1));
    [h,~,d]=cofdm.estimate_channel(raw,0.01,c);
    reference=integer_reference(raw,c);
    assert(isequal(h,reference));
    if amplitude==20, assert(d.saturations>0); end
    fprintf('PASS independent integer FIR amplitude=%g saturations=%d\n',amplitude,d.saturations);
end
% Missing earlier path: observed support at +10/+23 relative to real first.
score=1e-5*ones(193,1); score(100)=1; score(113)=0.1;
[first,info]=cofdm.choose_fft_window(score,1,100,c);
assert(first>=81 && first<=90 && info.offsetFromPeak<=-10);
% Full CP length: do not create an early window beyond the true safe set.
score=1e-5*ones(193,1); score(100)=1; score(69)=0.4;
first=cofdm.choose_fft_window(score,1,100,c); assert(first>=68 && first<=69);
fprintf('PASS centered CP window including weak-first fixture\n');
for p={struct('delays',0,'gains',1,'snrDb',Inf,'cfoHz',0,'offset',0), ...
        struct('delays',[0 10 23],'gains',[0.25 1 0.3j],'snrDb',22,'cfoHz',135e3,'offset',37), ...
        struct('delays',[0 31],'gains',[0.65 1],'snrDb',22,'cfoHz',-220e3,'offset',83)}
    for quantized=[false true]
        c.quantizedDecoder=quantized;
        payload=uint8(randi([0 255],c.payloadBytes,1)); wave=cofdm.tx(payload,13,c,code);
        [y,truth]=cofdm.channel(wave,c,p{1}); r=cofdm.rx(y,c,code);
        assert(r.ok && isequal(payload,r.payload) && r.channelSaturations==0);
        offset=r.sync.ltfUsefulStart-(truth.frameStart+c.stfPeriod*c.stfRepeats+c.ncp);
        assert(offset>=max(p{1}.delays)-c.ncp && offset<=min(p{1}.delays));
        fprintf('PASS fixed FIR + pilot ROM quantizedLDPC=%d FFT offset=%d\n',quantized,offset);
    end
end
for y={zeros(c.slotSamples,1),randn(c.slotSamples,1)+1j*randn(c.slotSamples,1), ...
        exp(1j*2*pi*0.031*(0:c.slotSamples-1).'),zeros(100,1)}
    s=cofdm.synchronize(y{1},c); assert(~s.ok);
end
fprintf('All fixed-module tests passed.\n');
end
function result=integer_reference(raw,c)
B=c.channelWordBits; F=c.channelFractionBits;
C=c.coefficientWordBits; G=c.coefficientFractionBits;
ri=saturate(int64(sign(real(raw)).*floor(abs(real(raw))*2^F+0.5)),B);
ii=saturate(int64(sign(imag(raw)).*floor(abs(imag(raw))*2^F+0.5)),B);
angle=2*pi*c.active*c.smoothingCenterDelay/c.nfft;
cr=saturate(int64(sign(cos(angle)).*floor(abs(cos(angle))*2^G+0.5)),C);
ci=saturate(int64(sign(sin(angle)).*floor(abs(sin(angle))*2^G+0.5)),C);
rr=saturate(shift_round(ri.*cr-ii.*ci,G),B);
im=saturate(shift_round(ri.*ci+ii.*cr,G),B);
kernel=int64([1 6 15 20 15 6 1]); result=zeros(size(raw));
for k=1:numel(c.active)
    sr=int64(0); si=int64(0); weight=int64(0);
    for t=-3:3
        j=find(c.active==c.active(k)+t,1);
        if ~isempty(j)
            sr=sr+kernel(t+4)*rr(j); si=si+kernel(t+4)*im(j);
            weight=weight+kernel(t+4);
        end
    end
    sr=saturate(sr,c.channelAccumulatorBits); si=saturate(si,c.channelAccumulatorBits);
    reciprocal=int64(floor(2^G/double(weight)+0.5));
    sr=saturate(shift_round(sr*reciprocal,G),B);
    si=saturate(shift_round(si*reciprocal,G),B);
    realOut=saturate(shift_round(sr*cr(k)+si*ci(k),G),B);
    imagOut=saturate(shift_round(si*cr(k)-sr*ci(k),G),B);
    result(k)=complex(double(realOut),double(imagOut))/2^F;
end
end
function y=shift_round(x,n)
y=sign(x).*idivide(abs(x)+int64(2^(n-1)),int64(2^n),'floor');
end
function y=saturate(x,bits)
y=max(int64(-2^(bits-1)),min(int64(2^(bits-1)-1),x));
end
