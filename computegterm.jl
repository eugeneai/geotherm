using DataFrames
using CSV
using Plot

# geotherm parameters
# q0 = [30:10:120];     # [mW/m^2] surface heat flow
q0 = 40;                # [mW/m^2] surface heat flow

D = 16;                 # [km] thickness of upper crust
zbot = [16,23,39,300];  # [km] base of lithospheric layers
zmax = 225;             # [km] maximum depth of model
dz = 0.1;               # [km] depth step

P = 0.74;               #      partition coefficient for upper crustal
                        #      heat production
H = [0,0.4,0.4,0.02];   #      [uW/m^3] heat production of lithospheric
                        #               layers.  Note that upper crustal heat
                        #               production is computed by
                        #               A = (1 - P)*q0/D and is not zero.
# index to reference heat flow for elevation computation
iref = 3;

# figure;
# subplot(121); hold on;
for i = 1:length(q0)
    # compute surface heat production
    A0 = (1 - P) * q0[i] / D
    H[1] = A0

    # compute geotherm from emperical rather than long form
    T(:,i),z,k,A,q,alpha(:,i) = empgtherms(q0(i),zmax,dz,D,zbot,H)

    # thermal elevation from paper (de) from emperical geotherms (dem)
    if length(q0) > 1
        de[i] = sum(T(:,i).*alpha(:,i) - T(:,1).*alpha(:,1))*dz;
    end

    # plot results
    # plot(T(:,i),z,'k-');
end
#xxlabel('Temperature [\circC]');
#ylabel('Depth [km]');
#axis([0 ceil(max(T(:))/100)*100+100 0 zmax]);
#axis ij;
#axis square;
#set(gca,'Box','on');

if length(q0) > 1
    subplot(122); hold on;
    xlabel('Surface Heat Flow [mW/m^2]');
    ylabel('Elevation [km]');
    plot(q0,de-de(iref),'kx');
    axis square;
    set(gca,'Box','on');
else
    fprintf(' Depth [km]   Temperature [K]\n');
    for i = 1:length(z)
        fprintf('%7.2f       %7.2f\n',z(i),T(i));
    end
end
