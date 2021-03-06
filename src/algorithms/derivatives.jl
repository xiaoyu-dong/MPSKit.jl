# Given a state and it's environments, we can act on it

"""
    One-site derivative
"""
function ac_prime(x::MPSTensor,ham::MPOHamiltonian,leftenv,rightenv)
    ham.period == 1 || throw(ArgumentError("period mismatch (try ham[pos])"))

    toret = zero(x)
    for (i,j) in opkeys(ham,1)
        @tensor toret[-1,-2,-3]+=leftenv[i][-1,5,4]*x[4,2,1]*ham[1,i,j][5,-2,3,2]*rightenv[j][1,3,-3]
    end
    for (i,j) in scalkeys(ham,1)
        scal = ham.Os[1,i,j];
        @tensor toret[-1,-2,-3]+=leftenv[i][-1,5,4]*(scal*x)[4,-2,1]*rightenv[j][1,5,-3]
    end

    return toret
end

function ac_prime(x::MPSTensor,opp::MPOTensor,leftenv,rightenv)
    @tensor toret[-1 -2;-3]:=leftenv[-1,2,1]*x[1,3,4]*opp[2,-2,5,3]*rightenv[4,5,-3]
end

"""
    Two-site derivative
"""
function ac2_prime(x::MPOTensor,ham::MPOHamiltonian,leftenv,rightenv)
    ham.period == 2 || throw(ArgumentError("period mismatch (try ham[pos])"))

    toret=zero(x)

    for (i,j) in keys(ham,1)
        for k in 1:ham.odim
            contains(ham,2,j,k) || continue

            if isscal(ham,1,i,j) && isscal(ham,2,j,k)
                scal = ham.Os[1,i,j]*ham.Os[2,j,k]
                @tensor toret[-1,-2,-3,-4] += (scal*leftenv[i])[-1,7,6]*x[6,-2,-3,1]*rightenv[k][1,7,-4]
            elseif isscal(ham,1,i,j)
                scal = ham.Os[1,i,j]
                @tensor toret[-1,-2,-3,-4]+=(scal*leftenv[i])[-1,7,6]*x[6,-2,3,1]*ham[2,j,k][7,-3,2,3]*rightenv[k][1,2,-4]
            elseif isscal(ham,2,j,k)
                scal = ham.Os[2,j,k]
                @tensor toret[-1,-2,-3,-4]+=(scal*leftenv[i])[-1,7,6]*x[6,5,-3,1]*ham[1,i,j][7,-2,2,5]*rightenv[k][1,2,-4]
            else
                @tensor toret[-1,-2,-3,-4]+=leftenv[i][-1,7,6]*x[6,5,3,1]*ham[1,i,j][7,-2,4,5]*ham[2,j,k][4,-3,2,3]*rightenv[k][1,2,-4]
            end
        end

    end

    return toret
end
function ac2_prime(x::MPOTensor,opps::AbstractVector{<:MPOTensor},leftenv,rightenv)
    length(opps) == 2 || throw(ArgumentError("length(opps) = $(length(opps)) != 2"));
    @tensor toret[-1 -2;-3 -4]:=leftenv[-1,2,1]*x[1,3,4,5]*opps[1][2,-2,6,3]*opps[2][6,-3,7,4]*rightenv[5,7,-4]
end


"""
    Zero-site derivative (the C matrix to the right of pos)
"""
function c_prime(x,leftenv::AbstractVector,rightenv::AbstractVector)
    sum(zip(leftenv,rightenv)) do (le,re)
        c_prime(x,le,re)
    end
end

function c_prime(x, leftenv::MPSTensor,rightenv::MPSTensor)
    @tensor toret[-1;-2] := leftenv[-1,3,1]*x[1,2]*rightenv[2,3,-2]
end

#not breaking everything immediatly
function ac_prime(x::MPSTensor,pos::Int,mps::Union{FiniteMPS,InfiniteMPS,MPSComoving},cache::Union{FinEnv,MPOHamInfEnv,IDMRGEnv})
    ac_prime(x,cache.opp[pos],leftenv(cache,pos,mps),rightenv(cache,pos,mps))
end
function ac_prime(x::MPSTensor, row::Int,col::Int,mps::Union{InfiniteMPS,MPSMultiline}, envs::Union{MixPerMPOInfEnv,PerMPOInfEnv})
    ac_prime(x,envs.opp[row,col],leftenv(envs,row,col,mps),rightenv(envs,row,col,mps));
end
function ac2_prime(x::MPOTensor,pos::Int,mps::Union{FiniteMPS,InfiniteMPS,MPSComoving},cache::Union{FinEnv,MPOHamInfEnv,IDMRGEnv})
    ac2_prime(x,cache.opp[pos:pos+1],leftenv(cache,pos,mps),rightenv(cache,pos+1,mps));
end
function ac2_prime(x::MPOTensor, row::Int,col::Int,mps::Union{InfiniteMPS,MPSMultiline}, envs::Union{MixPerMPOInfEnv,PerMPOInfEnv})
    ac2_prime(x,envs.opp[row,col:col+1],leftenv(envs,row,col,mps),rightenv(envs,row,col+1,mps))
end
function c_prime(x::MPSBondTensor,pos::Int,mps::Union{FiniteMPS,InfiniteMPS,MPSComoving},cache)
    c_prime(x,leftenv(cache,pos+1,mps),rightenv(cache,pos,mps))
end
function c_prime(x::TensorMap, row::Int,col::Int, mps::Union{InfiniteMPS,MPSMultiline}, envs::Union{MixPerMPOInfEnv,PerMPOInfEnv})
    c_prime(x,leftenv(envs,row,col+1,mps),rightenv(envs,row,col,mps))
end

#allow calling them with CartesianIndices
ac_prime(x,pos::CartesianIndex,mps,envs) = ac_prime(x,Tuple(pos)...,mps,envs)
ac2_prime(x,pos::CartesianIndex,mps,envs) = ac2_prime(x,Tuple(pos)...,mps,envs)
c_prime(x,pos::CartesianIndex,mps,envs) = c_prime(x,Tuple(pos)...,mps,envs)

#downproject for approximate
function c_proj(pos,below,envs::OvlEnv)
    le = leftenv(envs,pos+1,below)
    re = rightenv(envs,pos,below)

    @tensor toret[-1;-2] := le[-1,1]*envs.above.CR[pos][1,2]*re[2,-2]
end
function c_proj(row,col,below,envs::MixPerMPOInfEnv)
    c_prime(envs.above.CR[row,col],leftenv(envs,row,col+1,below),rightenv(envs,row,col,below))
end
function ac_proj(pos,below,envs::OvlEnv)
    le = leftenv(envs,pos,below)
    re = rightenv(envs,pos,below)

    @tensor toret[-1 -2;-3] := le[-1,1]*envs.above.AC[pos][1,-2,2]*re[2,-3]
end
function ac_proj(row,col,below,envs::MixPerMPOInfEnv)
    ac_prime(envs.above.AC[row,col],envs.opp[row,col],leftenv(envs,row,col,below),rightenv(envs,row,col,below))
end
function ac2_proj(pos,below,envs::OvlEnv)
    le = leftenv(envs,pos,below)
    re = rightenv(envs,pos+1,below)

    @tensor toret[-1 -2;-3 -4] := le[-1,1]*envs.above.AC[pos][1,-2,2]*envs.above.AR[pos+1][2,-3,3]*re[3,-4]
end
function ac2_proj(row,col,below,envs::MixPerMPOInfEnv)
    @tensor ac2[-1 -2;-3 -4] := envs.above.AC[row,col][-1,-2,1]*envs.above.AR[row,col+1][1,-3,-4]
    ac2_prime(ac2,leftenv(envs,row,col+1,below),rightenv(envs,row,col+1,below))
end
