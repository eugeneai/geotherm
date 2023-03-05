# push!(LOAD_PATH,pwd())
using Revise
using DataFrames
using CSV
using Plots
using Debugger
using Formatting
using LaTeXStrings

includet("EmpgTherm.jl")
# using .EmpgTherm

# geotherm parameters
q0 = 30:10:120     # [mW/m^2] surface heat flow
#q0 = 40                 # [mW/m^2] surface heat flow

D = 16                  # [km] thickness of upper crust
zbot = [16,23,39,300]   # [km] base of lithospheric layers
zmax = 225              # [km] maximum depth of model
dz = 0.1                # [km] depth step

P = 0.74                #      partition coefficient for upper crustal
                        #      heat production
H = [0,0.4,0.4,0.02]    #      [uW/m^3] heat production of lithospheric
                        #               layers.  Note that upper crustal heat
                        #               production is computed by
                        #               A = (1 - P)*q0/D and is not zero.
# index to reference heat flow for elevation computation
iref = 3

# figure;
# subplot(121); hold on;
T = undef
alpha_ = undef
de=zeros(0)
labels=[]
plt = plot()
for i = 1:length(q0)
    global T, alpha_, de, labels, plt
    # compute surface heat production
    A0 = (1 - P) * q0[i] / D
    H[1] = A0

    # compute geotherm from emperical rather than long form
    # T[:,i],z,k,A,q,alpha_[:,i] = empgtherms(q0[i],zmax,dz,D,zbot,H)
    _T,z,k,A,q,_alpha_ = empgtherms(q0[i],zmax,dz,D,zbot,H)
    if T == undef
        T = _T
    else
        T = hcat(T,_T)
    end
    if alpha_ == undef
        alpha_ = _alpha_
    else
        alpha_ = hcat(alpha_,_alpha_)
    end

    # thermal elevation from paper (de) from emperical geotherms (dem)
    if length(q0) > 1
        de = vcat(de, sum(T[:,i].*alpha_[:,i] - T[:,1].*alpha_[:,1])*dz)
    end

    # plot results
    # plot(T(:,i),z,'k-');
    # format("q0[{}]={}", i, q0[i])
    label = format("q0[{}]={}", i, q0[i])
    push!(labels, label)
    # plot!(T[:,i], z, linewith=3)
    # plot!(plt, _T, z, label = label, linewith=3)
    plot!(plt, _T, z, label = label, linewith=3, yflip=true)
end
xlabel!(L"Temperature ${}^\circ$C");
ylabel!("Depth [km]");
ylims!(0, zmax)
xlims!(0, ceil(maximum(T[:])/100)*100+100)
#axis ij;
#axis square;
#set(gca,'Box','on');

# if length(q0) > 1
#     subplot(122); hold on;
#     xlabel('Surface Heat Flow [mW/m^2]');
#     ylabel('Elevation [km]');
#     plot(q0,de-de(iref),'kx');
#     axis square;
#     set(gca,'Box','on');
# else
#     fprintf(' Depth [km]   Temperature [K]\n');
#     for i = 1:length(z)
#         fprintf('%7.2f       %7.2f\n',z(i),T(i));
#     end
# end
savefig(plt, "geotherm.svg")
plt = undef


function main()
    println("Hello")
end
