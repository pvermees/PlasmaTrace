using KJ, Test, CSV, Infiltrator, DataFrames, Statistics
import Plots

function loadtest(verbose=false)
    myrun = load("data/Lu-Hf";instrument="Agilent")
    if verbose summarise(myrun;verbose=true,n=5) end
    return myrun
end

function plottest()
    myrun = loadtest()
    p = plot(myrun[1],["Hf176 -> 258","Hf178 -> 260"])
    @test display(p) != NaN
    p = plot(myrun[1],["Hf176 -> 258","Hf178 -> 260"], den="Hf178 -> 260")
    @test display(p) != NaN
end

function windowtest()
    myrun = loadtest()
    i = 2
    setSwin!(myrun[i],[(70,90),(100,140)])
    setBwin!(myrun[i],[(0,22)];seconds=true)
    setSwin!(myrun[i],[(37,65)];seconds=true)
    p = plot(myrun[i],["Hf176 -> 258","Hf178 -> 260"])
    @test display(p) != NaN
end

function blanktest()
    myrun = loadtest()
    blk = fitBlanks(myrun;nblank=2)
    dt = dwelltime(myrun)
    return myrun, dt, blk
end

function standardtest(verbose=false)
    myrun, blk = blanktest()
    standards = Dict("BP_gt" => "BP")
    setGroup!(myrun,standards)
    anchors = getAnchors("Lu-Hf",standards)
    if verbose
        println(anchors)
        summarise(myrun;verbose=true,n=5)
    end
end

function fixedLuHf()
    myrun, dt, blk = blanktest()
    method = "Lu-Hf"
    channels = Dict("d" => "Hf178 -> 260",
                    "D" => "Hf176 -> 258",
                    "P" => "Lu175 -> 175")
    glass = Dict("NIST612" => "NIST612p")
    setGroup!(myrun,glass)
    standards = Dict("BP_gt" => "BP")
    setGroup!(myrun,standards)
    fit = (drift=[-3.9225],
           down=[0.0,0.03362],
           mfrac=0.38426,
           PAcutoff=nothing,
           adrift=[-3.9225])
    return myrun, dt, blk, method, channels, glass, standards, fit
end

function predictest()
    myrun, dt, blk, method, channels, glass, standards, fit = fixedLuHf()
    samp = myrun[105]
    if samp.group == "sample"
        println("Not a standard")
    else
        pred = predict(samp,dt,method,fit,blk,channels,standards,glass)
        p = plot(samp,dt,method,channels,blk,fit,standards,glass;
                 transformation="log")
        @test display(p) != NaN
    end
    return samp,dt,method,fit,blk,channels,standards,glass,p
end
    
function partest(parname,paroffsetfact)
    samp,dt,method,fit,blk,channels,standards,glass,p = predictest()
    drift = fit.drift[1]
    down = fit.down[2]
    mfrac = fit.mfrac[1]
    for paroffset in paroffsetfact .* [-1,1]
        if parname=="drift"
            drift = fit.drift[1] + paroffset
        elseif parname=="down"
            down = fit.down[2] + paroffset
        elseif parname=="mfrac"
            mfrac = fit.mfrac[1] + paroffset
        end
        adjusted_fit = (drift=[drift],
                        down=[0.0,down],
                        mfrac=mfrac,
                        PAcutoff=nothing,
                        adrift=[drift])
        anchors = getAnchors(method,standards,false)
        offset = getOffset(samp,dt,channels,blk,adjusted_fit,anchors,"log")
        plotFitted!(p,samp,dt,blk,adjusted_fit,channels,anchors;
                    offset=offset,transformation="log",linecolor="red")
    end
    @test display(p) != NaN
end

function driftest()
    partest("drift",1.0)
end

function downtest()
    partest("down",4.0)
end

function mfractest()
    partest("mfrac",0.2)
end

function fractionationtest(all=true)
    myrun, dt, blk = blanktest()
    method = "Lu-Hf"
    channels = Dict("d" => "Hf178 -> 260",
                    "D" => "Hf176 -> 258",
                    "P" => "Lu175 -> 175")
    glass = Dict("NIST612" => "NIST612p")
    setGroup!(myrun,glass)
    standards = Dict("BP_gt" => "BP")
    setGroup!(myrun,standards)
    if all
        println("two separate steps: ")
        mf = fractionation(myrun,dt,method,blk,channels,glass)
        fit = fractionation(myrun,dt,method,blk,channels,standards,mf;
                            ndrift=1,ndown=1)
        println(fit)
        print("no glass: ")
        fit = fractionation(myrun,dt,method,blk,channels,standards,nothing;
                            ndrift=1,ndown=1)
        println(fit)
        println("two joint steps: ")
    end
    fit = fractionation(myrun,dt,"Lu-Hf",blk,channels,standards,glass;
                        ndrift=1,ndown=1)
    if (all)
        println(fit)
        return myrun, dt, blk, fit, channels, standards, glass
    else
        Ganchors = getAnchors(method,glass,true)
        Sanchors = getAnchors(method,standards,false)
        anchors = merge(Sanchors,Ganchors)
        return myrun, dt, blk, fit, channels, standards, glass, anchors
    end
end

function RbSrTest(show=true)
    myrun = load("data/Rb-Sr",instrument="Agilent")
    method = "Rb-Sr"
    channels = Dict("d"=>"Sr88 -> 104",
                    "D"=>"Sr87 -> 103",
                    "P"=>"Rb85 -> 85")
    standards = Dict("MDC_bt" => "MDC -")
    setGroup!(myrun,standards)
    blank = fitBlanks(myrun;nblank=2)
    dt = dwelltime(myrun)
    fit = fractionation(myrun,dt,method,blank,channels,standards,8.37861;
                        ndown=0,ndrift=1,verbose=false)
    anchors = getAnchors(method,standards)
    if show
        p = plot(myrun[2],dt,channels,blank,fit,anchors,
                 transformation="log")#,den="Sr88 -> 104")
        @test display(p) != NaN
    end
    export2IsoplotR(myrun,dt,method,channels,blank,fit;
                    prefix="Entire",fname="Entire.json")
    return myrun, dt, blank, fit, channels, standards, anchors
end

function KCaTest(show=true)
    myrun = load("data/K-Ca",instrument="Agilent")
    method = "K-Ca"
    channels = Dict("d"=>"Ca44 -> 63",
                    "D"=>"Ca40 -> 59",
                    "P"=>"K39 -> 39")
    standards = Dict("EntireCreek_bt" => "EntCrk")
    setGroup!(myrun,standards)
    blank = fitBlanks(myrun;nblank=2)
    dt = dwelltime(myrun)
    fit = fractionation(myrun,dt,method,blank,channels,standards,nothing;
                        ndown=0,ndrift=1,verbose=false)
    anchors = getAnchors(method,standards)
    if show
        p = plot(myrun[3],dt,channels,blank,fit,anchors,
                 transformation="log",den=nothing)
        @test display(p) != NaN
    end
    export2IsoplotR(myrun,dt,method,channels,blank,fit,
                    prefix="EntCrk",fname="Entire_KCa.json")
    return myrun, dt, blank, fit, channels, standards, anchors
end

function plot_residuals(Pm,Dm,dm,Pp,Dp,dp)
    Pmisfit = Pm.-Pp
    Dmisfit = Dm.-Dp
    dmisfit = dm.-dp
    pP = Plots.histogram(Pmisfit,xlab="εP")
    pD = Plots.histogram(Dmisfit,xlab="εD")
    pd = Plots.histogram(dmisfit,xlab="εd")
    pPD = Plots.plot(Pmisfit,Dmisfit;
                     seriestype=:scatter,xlab="εP",ylab="εD")
    pPd = Plots.plot(Pmisfit,dmisfit;
                     seriestype=:scatter,xlab="εP",ylab="εd")
    pDd = Plots.plot(Dmisfit,dmisfit;
                     seriestype=:scatter,xlab="εD",ylab="εd")
    pDP = Plots.plot(Dmisfit,Pmisfit;
                     seriestype=:scatter,xlab="εD",ylab="εP")
    pdP = Plots.plot(dmisfit,Pmisfit;
                     seriestype=:scatter,xlab="εd",ylab="εP")
    pdD = Plots.plot(dmisfit,Dmisfit;
                     seriestype=:scatter,xlab="εd",ylab="εD")
    p = Plots.plot(pP,pDP,pdP,
                   pPD,pD,pdD,
                   pPd,pDd,pd;legend=false)
    @test display(p) != NaN    
end

function histest(;LuHf=false,show=true)
    if LuHf
        myrun,dt,blk,fit,channels,standards,glass,anchors =
            fractionationtest(false)
        standard = "BP_gt"
    else
        myrun,dt,blk,fit,channels,standards,anchors = RbSrTest(false)
        standard = "MDC_bt"
    end
    print(fit)
    pooled = pool(myrun;signal=true,group=standard)
    anchor = anchors[standard]
    pred = predict(pooled,dt,fit,blk,channels,anchor)
    Pm = pooled[:,channels["P"]]
    Dm = pooled[:,channels["D"]]
    dm = pooled[:,channels["d"]]
    Pp = pred[:,"P"]
    Dp = pred[:,"D"]
    dp = pred[:,"d"]
    if show
        plot_residuals(Pm,Dm,dm,Pp,Dp,dp)
        df = DataFrame(Pm=Pm,Dm=Dm,dm=dm,Pp=Pp,Dp=Dp,dp=dp)
        CSV.write("pooled_" * standard * ".csv",df)
    end
    return anchors, fit, Pm, Dm, dm
end

function processtest()
    myrun = load("data/Lu-Hf",instrument="Agilent")
    dt = dwelltime(myrun)
    method = "Lu-Hf";
    channels = Dict("d"=>"Hf178 -> 260",
                    "D"=>"Hf176 -> 258",
                    "P"=>"Lu175 -> 175");
    standards = Dict("Hogsbo_gt" => "hogsbo")#"BP_gt" => "BP")#
    glass = Dict("NIST612" => "NIST612p")
    blk, fit = process!(myrun,dt,method,channels,standards,glass,
                        nblank=2,ndrift=1,ndown=1);
    p = plot(myrun[2],dt,method,channels,blk,fit,standards,glass,
             transformation="log",den=nothing)#"Hf176 -> 258",);
    @test display(p) != NaN
end

function PAtest(verbose=false)
    myrun = load("data/Lu-Hf",instrument="Agilent")
    dt = dwelltime(myrun)
    method = "Lu-Hf"
    channels = Dict("d"=>"Hf178 -> 260",
                    "D"=>"Hf176 -> 258",
                    "P"=>"Lu175 -> 175")
    standards = Dict("Hogsbo_gt" => "hogsbo")
    glass = Dict("NIST612" => "NIST612p")
    cutoff = 1e7
    blk, fit = process!(myrun,dt,method,channels,standards,glass;
                        PAcutoff=cutoff,nblank=2,ndrift=1,ndown=1)
    ratios = averat(myrun,dt,channels,blk,fit)
    if verbose println(first(ratios,5)) end
    return ratios
end

function exporttest()
    ratios = PAtest()
    selection = prefix2subset(ratios,"BP") # "hogsbo"
    CSV.write("BP.csv",selection)
    export2IsoplotR(selection,"Lu-Hf",fname="BP.json")
end

function UPbtest()
    myrun = load("data/U-Pb",instrument="Agilent",head2name=false)
    dt = dwelltime(myrun)
    method = "U-Pb"
    standards = Dict("Plesovice_zr" => "STDCZ",
                     "91500_zr" => "91500")
    glass = Dict("NIST610" => "610",
                 "NIST612" => "612")
    channels = Dict("d"=>"Pb207","D"=>"Pb206","P"=>"U238")
    blank, pars = process!(myrun,dt,"U-Pb",channels,standards,glass,
                           nblank=2,ndrift=1,ndown=1)
    export2IsoplotR(myrun,dt,method,channels,blank,pars,fname="UPb.json")
    p = plot(myrun[1],dt,method,channels,blank,pars,
             standards,glass,transformation="log",den="Pb206")
    @test display(p) != NaN
end

function iCaptest(verbose=true)
    myrun = load("data/iCap",instrument="ThermoFisher")
    if verbose summarise(myrun;verbose=true,n=5) end
end

function carbonatetest(verbose=false)
    method = "U-Pb"
    myrun = load("data/carbonate",instrument="Agilent")
    dt = dwelltime(myrun)
    standards = Dict("WC1_cc"=>"WC1")
    glass = Dict("NIST612"=>"NIST612")
    channels = Dict("d"=>"Pb207","D"=>"Pb206","P"=>"U238")
    blk, fit = process!(myrun,dt,method,channels,standards,glass,
                        nblank=2,ndrift=1,ndown=1,verbose=verbose)
    export2IsoplotR(myrun,dt,method,channels,blk,fit;
                    prefix="Duff",fname="Duff.json")
    p = plot(myrun[3],dt,method,channels,blk,fit,standards,glass;
             transformation=nothing,num=["Pb207"],den="Pb206",ylim=[-0.02,0.3])
    @test display(p) != NaN
end

function timestamptest(verbose=true)
    myrun = load("data/timestamp/MSdata.csv",
                 "data/timestamp/timestamp.csv";
                 instrument="Agilent")
    if verbose summarise(myrun;verbose=true,n=5) end
    p = plot(myrun[2];transformation="sqrt")
    @test display(p) != NaN
end

function mineraltest()
    internal = getInternal("zircon","Si29")
end

function concentrationtest()
    method = "concentrations"
    myrun = load("data/Lu-Hf",instrument="Agilent")
    internal = ("Al27 -> 27",1.2e5)
    glass = Dict("NIST612" => "NIST612p")
    setGroup!(myrun,glass)
    blk, fit = process!(myrun,internal,glass;nblank=2)
    p = plot(myrun[4],blk,fit,internal[1];
             transformation="log",den=internal[1])
    conc = concentrations(myrun,blk,fit,internal)
    @test display(p) != NaN
end

module test
function extend!(_KJ::AbstractDict)
    old = _KJ["tree"]["top"]
    _KJ["tree"]["top"] = (message = "test", help = "test", action = old.action)
end
export KJtree!
end
using .test
function extensiontest(verbose=true)
    TUI(test,logbook="logs/extension.log")
end

function TUItest()
    TUI(logbook="logs/test.log",reset=true)
end

Plots.closeall()

if true
    #=@testset "load" begin loadtest(true) end
    @testset "plot raw data" begin plottest() end
    @testset "set selection window" begin windowtest() end
    @testset "set method and blanks" begin blanktest() end
    @testset "assign standards" begin standardtest(true) end
    @testset "predict" begin predictest() end
    @testset "predict drift" begin driftest() end
    @testset "predict down" begin downtest() end
    @testset "predict mfrac" begin mfractest() end
    @testset "fit fractionation" begin fractionationtest(true) end
    @testset "Rb-Sr" begin RbSrTest() end
    @testset "K-Ca" begin KCaTest() end
    @testset "hist" begin histest() end
    @testset "process run" begin processtest() end
    @testset "PA test" begin PAtest(true) end
    @testset "export" begin exporttest() end
    @testset "U-Pb" begin UPbtest() end
    @testset "iCap test" begin iCaptest() end
    @testset "carbonate test" begin carbonatetest() end
    @testset "timestamp test" begin timestamptest() end
    @testset "stoichiometry test" begin mineraltest() end=#
    @testset "concentration test" begin concentrationtest() end
    #=@testset "extension test" begin extensiontest() end
    @testset "TUI test" begin TUItest() end=#
else
    TUI()
end
