function [T,z,lambda,A,q,alpha] = empgtherms(q0,maxz,dz,D,zbot,H);
% EMPGTHERMS - Computes empirical geotherms.
%
% Based on method by Hasterok & Chapman [EPSL, 2011] method.
%
% Example Call:
%    [T,z,k,A,q] = empgtherms(q0,maxz,dz,D,zbot,H);
%
% Inputs:
%    q0    - Surface heat flow          mW/m^2
%    maxz  - Maximum depth of model     km
%    dz    -
%    D     - Thickness of upper crust   km
%    zbot  - Depth to layer base        km
%    H     - Layer heat production      muW/m^3
%    zmoho - Depth to the moho          km
%
% Outputs:
%    T     - Temperature as a function of depth         C
%    z     - Depth                                      meters
%    lambda- Thermal conductivity                       W/m/K
%    A     - Heat production                            W/m^3
%    q     - Heat flow                                  W/m^2
%
% Last Modified: 15 March 2008 by D. Hasterok

% Depths
z = [0:dz:maxz]'; % m    Depth vector
lenz = length(z);
g = 10;
rhoc = 2850;
rhom = 3340;
zmoho = zbot(3);

% Heat Production
lambda = zeros([length(z)-1 1]);
alpha = zeros([length(z) 1]);
A = zeros([length(z)-1 1]);
for i = 1:length(zbot)
    if i ~= 1
        il = iu;
        iu = round(zbot(i)/dz);
    else
        il = 1;
        iu = round(D/dz);
    end

    A(il:iu) = H(i);
end
A = A(:);

% Temperature Conditions
T0 = 0 + 273;      % degC      Surface Temperature
Ta0 = 1300 + 273;  % degC      Adiabatic Potential
dT = 0.3;       % degC/km   Adiabatic Gradient

% Adiabatic Gradient
Ta = Ta0 + z*dT;

% Compute Heat Flow
q = q0*ones(size(z));
q(2:lenz) = q(2:lenz) - cumsum(A(1:lenz-1))*dz;

% Compute Temperature
T = zeros(size(z));
T(1) = T0;
adiabat = 0;
ik = 1;
for i = 1:lenz-1
    zsg = (1.4209 + exp(3.9073e-3*T(i) - 6.8041) - rhoc*g*zmoho*1e-6)/(rhom*g*1e-6);
    if z(i) - zmoho > zsg
        ik = length(zbot) + 1;
    elseif zbot(ik) < z(i+1)
        ik = ik + 1;
    end

    if i ~= 1
        [T(i+1),lambda(i)] = tccomp(ik,zmoho,z(i+1),dz,T(i),q(i),lambda(i-1),A(i));
    else
        [T(i+1),lambda(i)] = tccomp(ik,zmoho,z(i+1),dz,T(i),q(i),3,A(i));

        alpha(i) = empexpansivity(ik,zmoho,z(1),T(1));
    end
    alpha(i+1) = empexpansivity(ik,zmoho,z(i+1),T(i+1));

    if T(i+1) > Ta(i+1)
        adiabat = 1;
        break
    end
end

if adiabat == 0
    T = T - 273;
    return
end


% If the geotherm reaches the adiabat compute adiabat
for j = i+1:lenz
    T(j) = Ta(j);
    q(j) = q(j-1);
    A(j) = A(j-1);

    alpha(j) = empexpansivity(ik,zmoho,z(j),T(j));

    if j == lenz
        break;
    end

    zsg = (1.4209 + exp(3.9073e-3*Ta(i) - 6.8041) - rhoc*g*zmoho*1e-6) ...
         / (rhom*g*1e-6);

    if z(i) > zsg
        ik = length(zbot) + 1;
    elseif zbot(ik) < z(j+1)
        ik = ik + 1;
    end
    % thermal conductivity coefficients
    lambda(j) = thermcond(ik,zmoho,z(j),0.5*(Ta(j) + Ta(j+1)));
end

T = T - 273;

return


function [T,lambda] = tccomp(ik,zmoho,z,dz,tau,q,lambda0,A)

% Starting temperature guess
dT0 = q/lambda0*dz;
guess = tau + dT0;

c = 1;
tol = 1e-3;
maxit = 10;

gamma = (q*dz - 0.5*A*dz^2);

while 1
    % thermal conductivity
    [lambda,dlambda] = thermcond(ik,zmoho,z,0.5*(guess+tau));

    f  = guess - (tau + gamma/lambda);
    df = 1 + gamma*dlambda/lambda^2;

    result = guess - f/df;

    % Update Tolerance
    if abs(result - guess) < tol
        break;
    end

    if c > maxit
        warning('TCCOMP did not converge...');
    end

    % New dT becomes guess dT0
    guess = result;
    c = c + 1;
end

T = guess;

% Compute k
lambda = thermcond(ik,zmoho,z,0.5*(T+tau));

return


function [lambda,varargout] = thermcond(ik,zmoho,z,T)
% [lambda,dlambda] = thermcond(ik,z,T)

k = kcoef(ik,T);
g = 10;
rhoc = 2850;
rhom = 3340;

if z < zmoho
    P = 1e-6*rhoc*g*z;
else
    P = 1e-6*(rhoc*g*zmoho + rhom*g*(z - zmoho));
end

lambda = (k(1) + k(2)/T + k(3)*T^2)*(1 + k(4)*P);
if nargout == 2
    varargout{1} = (2*k(3)*T - k(2)*T^-2)*(1 + k(4)*P);
end

return


function k = kcoef(ik,T)

ka = [1.496  398.84  4.573e-7 0.0950;
      1.733  194.59  2.906e-7 0.0788;
      1.723  219.88  1.705e-7 0.0520;
      2.271  681.12 -1.259e-7 0.0399;
      2.371  669.40 -1.288e-7 0.0384];

kb = [2.964 -495.29  0.866e-7 0.0692;
      2.717 -398.93  0.032e-7 0.0652;
      2.320  -96.98 -0.981e-7 0.0463];

if ik <= 3 & T > 844
    k = kb(ik,:);
else
    k = ka(ik,:);
end

return


function alpha = empexpansivity(ia,zmoho,z,T)

a = acoef(ia,T);
g = 10;
rhoc = 2850;
rhom = 3340;
zmoho = 39;

if z < zmoho
    P = 1e-6*rhoc*g*z;
else
    P = 1e-6*(rhoc*g*zmoho + rhom*g*(z - zmoho));
end

alpha = (a(1) + a(2)*T + a(3)*T.^-2)*(1 + a(4)*P);

return


function a = acoef(ia,T)

aa = [2.355e-5 3.208e-8 -0.7938 -0.1193;
      2.020e-5 2.149e-8 -0.6315 -0.1059;
      2.198e-5 0.921e-8 -0.1820 -0.0626;
      3.036e-5 0.925e-8 -0.2730 -0.0421;
      3.026e-5 0.906e-8 -0.3116 -0.0408];

ab = [1.741e-5 0.500e-8 -0.3094 -0.0778;
      1.663e-5 0.602e-8 -0.3364 -0.0745;
      2.134e-5 0.711e-8 -0.1177 -0.0563];

if ia <= 3 & T > 844
    a = ab(ia,:);
else
    a = aa(ia,:);
end

return
