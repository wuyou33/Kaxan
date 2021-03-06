% uuvSimRun.m     e.anderlini@ucl.ac.uk     15/02/2018
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% This script simulates the dynamics of an UUV using trajectory control
% with adaptive model predictive control. The file relies on fast restart
% to simulate the ROV picking up an object.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%% Clean up:
clear;
close all;

%% Initialization:
% Run the set-up file:
rovSimSetup;
tEnd1 = mdl.tEnd/2;

% Initial conditions:
ics = zeros(12,1);             % initial conditions (m & rad)
v_c = [0;0;0;0;0;0];           % current velocity (m/s)

% Pre-processing:
T = [rov.T(1:3,:);rov.T(6,:)]; % thrust allocation matrix for 4 DOF
Tinv = pinv(T);                % inverse of the thrust allocation matrix

%% Generate the LTI model of the Kaxan ROV in 4 DOF:
% M = [rov.M_B(1:3,1:3),rov.M_B(1:3,6);rov.M_B(6,1:3),rov.M_B(6,6)] + ...
%     [rov.M_A(1:3,1:3),rov.M_A(1:3,6);rov.M_A(6,1:3),rov.M_A(6,6)];
% D = [rov.D_l(1:3,1:3),rov.D_l(1:3,6);rov.D_l(6,1:3),rov.D_l(6,6)];
% G = zeros(4);
% M_inv = pinv(M);
% 
% % Create the state-space matrices:
% A = [zeros(4),eye(4);-M_inv*G,-M_inv*D];
% B = [zeros(4);M_inv];
% E = [zeros(4);M_inv];
% C = eye(8);

% Load the identified system as an alternative:
load('ss_rov.mat');
% Define the time step of the model predictive control:
dt = 0.1;
% Convert it to discrete time:
sysd = c2d(sys,dt);
% Extract the matrices of the discrete system to initialize adaptive MPC:
Ad = sysd.A;
Bd = sysd.B;
Cd = sysd.C;
Dd = sysd.D;
A = sys.A;
B = sys.B;
C = sys.C;
D = sys.D;

%% MPC:
% Define variable names:
sysd.InputName = {'T1','T2','T3','T4','d'};
% Define the indices of the model variables:
sysd.InputGroup.ManipulatedVariables = [1,2,3,4];
% Define the index of the disturbance:
sysd.InputGroup.MeasuredDisturbances = 5;

% Define the prediction and control horizons:
p = 25;
m = 10;
% Define other parameters:
nu = 4;   % no. manipulated variables (4 DOF thrust vector)
W.MV     = zeros(1,nu);       % manipulated variables weights
W.MVRate = 0.1*ones(1,nu);    % manipulated variables increment weights
W.OV     = [1,1,1,1,0,0,0,0]; % output variables weights
% Define parameters for adaptive control:
X  = zeros(8,1);
DX = zeros(8,1);
Y  = zeros(8,1);
U  = zeros(5,1);

% Initialize the model predictive control object:
mpc_kaxan = mpc(sysd,dt,p,m,W);

%% On-line Recursive Least-Squares Estimator preparation:
% Specify values for the covariance matrix:
R = 0.01*eye(12);

tic;
%% Load the Simulink file:
% Simulink file:
sfile = 'uuvSim_ampc';
% Load the Simulink file:
load_system(sfile);

%% Run the first part of the simulation with the Kaxan ROV:
sout = sim(sfile,'StopTime',num2str(tEnd1-mdl.tStep));

% Extract the data to be plotted:
t = sout.tout;
x = sout.get('logsout').getElement('state').Values.Data;
f = [sout.get('logsout').getElement('thrust').Values.Data,...
    sout.get('logsout').getElement('forces').Values.Data];
tf = sout.get('logsout').getElement('control').Values.Data;
V = sout.get('logsout').getElement('V').Values.Data;

close_system(sfile);

%% Run the second part of the simulation with the ROV carrying the sphere:
clear rov d mpc_kaxan;
% Load new simulation data:
load('rov_sphere.mat');
ics = x(end,:);
% Recompute the disturbance data:
d = [trj(1:101,1).^2;ones(length(trj)-101,1)];
d = [trj(:,1),d];
% Load the new MPC controller:
load('ss_rov_sphere.mat');
sysd = c2d(sys,dt);
% Extract the matrices of the discrete system to initialize adaptive MPC:
Ad = sysd.A;
Bd = sysd.B;
Cd = sysd.C;
Dd = sysd.D;
A = sys.A;
B = sys.B;
C = sys.C;
D = sys.D;
% Define variable names:
sysd.InputName = {'T1','T2','T3','T4','d'};
% Define model variables:
sysd.InputGroup.ManipulatedVariables = [1,2,3,4];
sysd.InputGroup.MeasuredDisturbances = 5;
mpc_kaxan = mpc(sysd,dt,p,m,W);
% Re-load the Simulink file:
load_system(sfile);
% Re-run Simulink:
sout = sim(sfile,'StopTime',num2str(tEnd1));

close_system(sfile);
toc;

%% Post-processing:
% Extract the data to be plotted:
t = [t;sout.tout+tEnd1];
x = [x;sout.get('logsout').getElement('state').Values.Data];
f = [f;sout.get('logsout').getElement('thrust').Values.Data,...
    sout.get('logsout').getElement('forces').Values.Data];
tf = [tf;sout.get('logsout').getElement('control').Values.Data];
V = [V;sout.get('logsout').getElement('V').Values.Data];

% Clip the thruster force:
ll_520 = rov.coeffs(1,1)*(-5)^3+rov.coeffs(1,2)*(-5)^2+...
    rov.coeffs(1,3)*(-5)+rov.coeffs(1,4);
ul_520 = rov.coeffs(1,1)*5^3+rov.coeffs(1,2)*5^2+...
    rov.coeffs(1,3)*5+rov.coeffs(1,4);
ll_540 = rov.coeffs(2,1)*(-5)^3+rov.coeffs(2,2)*(-5)^2+...
    rov.coeffs(2,3)*(-5)+rov.coeffs(2,4);
ul_540 = rov.coeffs(2,1)*5^3+rov.coeffs(2,2)*5^2+...
    rov.coeffs(2,3)*5+rov.coeffs(1,4);
for i=1:length(tf)
    tf(i,1) = min(tf(i,1),ul_520);
    tf(i,1) = max(tf(i,1),ll_520);
    tf(i,2) = min(tf(i,2),ul_520);
    tf(i,2) = max(tf(i,2),ll_520);
    tf(i,3) = min(tf(i,3),ul_540);
    tf(i,3) = max(tf(i,3),ll_540);
    tf(i,4) = min(tf(i,4),ul_540);
    tf(i,4) = max(tf(i,4),ll_540);
end

% Plot the AUV's motions:
plotMotions(t,x);

% % Plot the AUV's forces:
% plotForces(t,f);
% Plot the force in each thruster:
plotThrustersForces(t,tf);
% Plot the voltage in each thruster:
% plotThrustersVoltage(t,V);


% % Plot the AUV's path:
% plotPath(x,waypoints);
% % Animate the AUV's motion:
% animateAUV(t,x,50,1,8);