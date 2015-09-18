
function [gradient,lb,meanll,varll] = mocap_dtsbn_stoc_gradient(v,parameters,prevMean,prevVar)

alpha = 0.8;

W1 = parameters{1}; % J*J*nt
W2 = parameters{2}; % K*J
W3 = parameters{3}; % J*K*nt
W4 = parameters{4}; % K*K*nt
W5 = parameters{5}; % M*K
W5prime = parameters{6}; % M*K
W6 = parameters{7}; % K*M*nt
W7 = parameters{8}; % M*M*nt
W7prime = parameters{9}; % M*M*nt

U1 = parameters{10}; % J*J*nt
U2 = parameters{11}; % J*K
U3 = parameters{12}; % J*K*nt
U4 = parameters{13}; % K*K*nt
U5 = parameters{14}; % K*M
U6 = parameters{15}; % K*M*nt

b1  = parameters{16}; % J*1
b2  = parameters{17}; % K*1
b3  = parameters{18}; % M*1
b3prime  = parameters{19}; % M*1
c1  = parameters{20}; % J*1
c2  = parameters{21}; % K*1

A1 = parameters{22}; % 1*L
A2 = parameters{23}; % L*M

[~,J,nt] = size(W1); [K,~] = size(W2); [M,T] = size(v);

%% feed-forward step
h = zeros(K,T); z = zeros(J,T);
% sampling
h(:,1) = double(sigmoid(U5*v(:,1)+c2)>rand(K,1));
z(:,1) = double(sigmoid(U2*h(:,1)+c1)>rand(J,1));

for t = 2:T
    cc2 = zeros(K,1);  cc1 = zeros(J,1); 
    for delay = 1:min(t-1,nt) 
        cc2 = cc2 + U4(:,:,delay)*h(:,t-delay)+U6(:,:,delay)*v(:,t-delay);
        cc1 = cc1 + U1(:,:,delay)*z(:,t-delay)+U3(:,:,delay)*h(:,t-delay);
    end;
    h(:,t) = double(sigmoid(U5*v(:,t)+cc2+c2)>rand(K,1));
    z(:,t) = double(sigmoid(U2*h(:,t)+cc1+c1)>rand(J,1));
end;

%% calculate lower bound 
term1 = zeros(J,T); term1h = zeros(K,T);
mu = zeros(M,T); logsigma = zeros(M,T); 
term3h = zeros(K,T); term3 = zeros(J,T);
% sampling
term1(:,1) = b1;
term1h(:,1) = W2*z(:,1)+b2;
mu(:,1) = W5*h(:,1)+b3;
logsigma(:,1) = W5prime*h(:,1)+b3prime;
term3h(:,1) = U5*v(:,1)+c2;
term3(:,1) = U2*h(:,1)+c1;

for t = 2:T
    bb1 = zeros(J,1); bb2 = zeros(K,1); bb3 = zeros(M,1); 
    cc2 = zeros(K,1); cc1 = zeros(J,1); bb3prime = zeros(M,1);
    for delay = 1:min(t-1,nt)
        bb1 = bb1 + W1(:,:,delay)*z(:,t-delay)+W3(:,:,delay)*h(:,t-delay);
        bb2 = bb2 + W4(:,:,delay)*h(:,t-delay)+W6(:,:,delay)*v(:,t-delay);
        bb3 = bb3 + W7(:,:,delay)*v(:,t-delay);
        bb3prime = bb3prime + W7prime(:,:,delay)*v(:,t-delay);
        cc2 = cc2 + U4(:,:,delay)*h(:,t-delay)+U6(:,:,delay)*v(:,t-delay);
        cc1 = cc1 + U1(:,:,delay)*z(:,t-delay)+U3(:,:,delay)*h(:,t-delay);
    end;
    term1(:,t) = bb1+b1;
    term1h(:,t) = W2*z(:,t)+bb2+b2;
    mu(:,t) = W5*h(:,t)+bb3+b3;
    logsigma(:,t) = W5prime*h(:,t)+bb3prime+b3prime;
    term3h(:,t) = U5*v(:,t)+cc2+c2;
    term3(:,t) = U2*h(:,t)+cc1+c1;
end;

logprior = sum(term1.*z-log(1+exp(term1))) + ...
    sum(term1h.*h-log(1+exp(term1h))) ; % 1*T
loglike = -sum(logsigma + (v-mu).^2./(2*exp(2*logsigma))+1/2*log(2*pi)); % 1*T
logpost = sum(term3.*z-log(1+exp(term3))) +...
    sum(term3h.*h-log(1+exp(term3h))); % 1*T
ll = logprior + loglike - logpost; % 1*T
lb = mean(ll);

ll = ll - A1*tanh(A2*v);

if prevMean == 0 && prevVar == 0
    meanll = mean(ll);
    varll = var(ll);
else
    meanll = alpha*prevMean + (1-alpha)*mean(ll); 
    varll = alpha*prevVar + (1-alpha)*var(ll);
end;

ll = (ll-meanll)./max(1,sqrt(varll));

%% gradient information
% model parameters
mat1 = z - sigmoid(term1); % J*T
grads.W1 = zeros(J,J,nt); grads.W3 = zeros(J,K,nt);
for delay = 1:nt
    grads.W1(:,:,delay) = mat1(:,delay+1:T)*z(:,1:T-delay)'/(T-delay); % J*J
    grads.W3(:,:,delay) = mat1(:,delay+1:T)*h(:,1:T-delay)'/(T-delay); % J*K
end;
grads.b1 = sum(mat1,2)/T; % J*1

mat1h = h - sigmoid(term1h); % K*T
grads.W2 = mat1h*z'/T; % K*J
grads.W4 = zeros(K,K,nt); grads.W6 = zeros(K,M,nt);
for delay = 1:nt
    grads.W4(:,:,delay) = mat1h(:,delay+1:T)*h(:,1:T-delay)'/(T-delay); % K*K
    grads.W6(:,:,delay) = mat1h(:,delay+1:T)*v(:,1:T-delay)'/(T-delay); % K*M
end;
grads.b2 = sum(mat1h,2)/T; % M*1


mat2 = (v-mu)./(exp(2*logsigma)); % M*T
mat2p = (v-mu).^2./(exp(2*logsigma))-1; % M*T
grads.W5 = mat2*h'/T ; % M*J
grads.W5prime = mat2p*h'/T ; % M*J
grads.W7 = zeros(M,M,nt);
grads.W7prime = zeros(M,M,nt);
for delay = 1:nt
    grads.W7(:,:,delay) = mat2(:,delay+1:T)*v(:,1:T-delay)'/(T-delay); % M*M
    grads.W7prime(:,:,delay) = mat2p(:,delay+1:T)*v(:,1:T-delay)'/(T-delay); % M*M
end;
grads.b3 = sum(mat2,2)/T; % M*1
grads.b3prime = sum(mat2p,2)/T; % M*1

% recognition parameters
mat3 = bsxfun(@times,z-sigmoid(term3),ll); % J*T
grads.U2 = mat3*h'/T; % J*K
grads.U1 = zeros(J,J,nt); grads.U3 = zeros(J,K,nt);
for delay = 1:nt
    grads.U1(:,:,delay) = mat3(:,delay+1:T)*z(:,1:T-delay)'/(T-delay); % J*J
    grads.U3(:,:,delay) = mat3(:,delay+1:T)*h(:,1:T-delay)'/(T-delay); % J*M
end;
grads.c1 = sum(mat3,2)/T; % J*1 

mat3h = bsxfun(@times,h-sigmoid(term3h),ll); % K*T
grads.U5 = mat3h*v'/T; % K*M
grads.U4 = zeros(K,K,nt); grads.U6 = zeros(K,M,nt);
for delay = 1:nt
    grads.U4(:,:,delay) = mat3h(:,delay+1:T)*h(:,1:T-delay)'/(T-delay); % K*K
    grads.U6(:,:,delay) = mat3h(:,delay+1:T)*v(:,1:T-delay)'/(T-delay); % K*M
end;
grads.c2 = sum(mat3h,2)/T; % K*1

grads.A1 = sum(bsxfun(@times,tanh(A2*v),ll),2)'/T; % 1*L 
tmp1 = bsxfun(@times,1-tanh(A2*v).^2,ll); %L*T
tmp2 = bsxfun(@times,tmp1,A1'); % L*T
grads.A2 = tmp2*v'/T;

%% collection
gradient{1} = grads.W1;
gradient{2} = grads.W2;
gradient{3} = grads.W3;
gradient{4} = grads.W4;
gradient{5} = grads.W5;
gradient{6} = grads.W5prime;
gradient{7} = grads.W6;
gradient{8} = grads.W7;
gradient{9} = grads.W7prime;

gradient{10} = grads.U1;
gradient{11} = grads.U2;
gradient{12} = grads.U3;
gradient{13} = grads.U4;
gradient{14} = grads.U5;
gradient{15} = grads.U6;

gradient{16} = grads.b1;    
gradient{17} = grads.b2; 
gradient{18} = grads.b3; 
gradient{19} = grads.b3prime; 
gradient{20} = grads.c1; 
gradient{21} = grads.c2; 

gradient{22} = grads.A1; 
gradient{23} = grads.A2; 

end        
