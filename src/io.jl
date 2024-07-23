"""
load

Read mass spectrometer data

# Returns

- a vector of samples

# Methods

- `load(dname::AbstractString;
        instrument::AbstractString="Agilent",
        head2name::Bool=true)`
- `load(dfile::AbstractString,
        tfile::AbstractString;
        instrument::AbstractString="Agilent")`

# Arguments

- `dname`: directory containing mass spectrometer data files
- `instrument`: one of "Agilent" or "ThermoFisher"
- `head2name`: `true` if sample names should be read from the file headers.
               `false` if they should be extracted from the file names
- `dfile`: single data file
- `tfile`: laser timestamp file

# Examples
```julia
myrun = load("data/Lu-Hf";instrument="Agilent")
p = plot(myrun[1],["Hf176 -> 258","Hf178 -> 260"])
display(p)
```
"""
function load(dname::AbstractString;
              instrument::AbstractString="Agilent",
              head2name::Bool=true)
    fnames = readdir(dname)
    samples = Vector{Sample}(undef,0)
    datetimes = Vector{DateTime}(undef,0)
    ext = getExt(instrument)
    for fname in fnames
        if occursin(ext,fname)
            try
                pname = joinpath(dname,fname)
                samp = readFile(pname;
                                instrument=instrument,
                                head2name=head2name)
                push!(samples,samp)
                push!(datetimes,samp.datetime)
            catch e
                println("Failed to read "*fname)
            end
        end
    end
    order = sortperm(datetimes)
    sortedsamples = samples[order]
    sorteddatetimes = datetimes[order]
    dt = sorteddatetimes .- sorteddatetimes[1]
    runtime = Dates.value.(dt)
    duration = runtime[end] + sortedsamples[end].dat[end,1]
    for i in eachindex(sortedsamples)
        samp = sortedsamples[i]
        samp.dat.t = (samp.dat[:,1] .+ runtime[i])./duration
    end
    return sortedsamples
end
function load(dfile::AbstractString,
              tfile::AbstractString;
              instrument::AbstractString="Agilent")
    samples = Vector{Sample}(undef,0)
    datetimes = Vector{DateTime}(undef,0)
    data = timestamps = DataFrame()
    try
        data = readDat(dfile;instrument=instrument)[1]
    catch e
        println("Failed to read "*dfile)
    end
    try
        timestamps = CSV.read(tfile, DataFrame)
    catch e
        println("Failed to read "*tfile)
    end
    return parseData(data,timestamps)
end
export load

function readFile(fname::AbstractString;
                  instrument::AbstractString="Agilent",
                  head2name::Bool=true)
    dat, sname, datetime, header, skipto, footerskip =
        readDat(fname;instrument=instrument,head2name=head2name)
    select!(dat, [k for (k,v) in pairs(eachcol(dat)) if !all(ismissing, v)])
    i0 = geti0(dat[:,2:end])
    t0 = dat[i0,1]
    nr = size(dat,1)
    bwin = [(1,ceil(Int,i0*9/10))]
    swin = [(floor(Int,i0+(nr-i0)/10),nr)]
    return Sample(sname,datetime,dat,t0,bwin,swin,"sample")
end

function readDat(fname::AbstractString;
                 instrument::AbstractString="Agilent",
                 head2name::Bool=true)
    if instrument=="Agilent"
        sname, datetime, header, skipto, footerskip =
            readAgilent(fname,head2name)
    elseif instrument=="ThermoFisher"
        sname, datetime, header, skipto, footerskip =
            readThermoFisher(fname,head2name)
    else
        PTerror("unknownInstrument")
    end
    dat = CSV.read(
        fname,
        DataFrame;
        header = header,
        skipto = skipto,
        footerskip = footerskip,
        ignoreemptyrows = true,
        delim = ',',
    )
    return dat, sname, datetime, header, skipto, footerskip
end

function readAgilent(fname::AbstractString,
                     head2name::Bool=true)

    lines = split(readuntil(fname, "Time [Sec]"), "\n")
    snamestring = head2name ? lines[1] : fname
    sname = split(split(snamestring,r"[\\/]")[end],".")[1]
    datetimeline = lines[3]
    from = findfirst(":",datetimeline)[1]+2
    to = findfirst("using",datetimeline)[1]-2
    datetime = automatic_datetime(datetimeline[from:to])
    header = 4
    skipto = 5
    footerskip = 3
    
    return sname, datetime, header, skipto, footerskip
    
end

function readThermoFisher(fname::AbstractString,
                          head2name::Bool=true)

    lines = split(readuntil(fname, "Time"), "\n")
    snamestring = head2name ? split(lines[1],":")[1] : fname
    sname = split(split(snamestring,r"[\\/]")[end],".")[1]
    datetimeline = lines[1]
    from = findfirst(":",datetimeline)[1]+1
    to = findfirst(";",datetimeline)[1]-1
    datetime = automatic_datetime(datetimeline[from:to])
    header = 14
    skipto = 16
    footerskip = 0
    
    return sname, datetime, header, skipto, footerskip
    
end

function parseData(data::AbstractDataFrame,
                   timestamps::AbstractDataFrame)
    runtime = data[:,1] # "Time [Sec]"
    signal = data[:,2:end]
    total = sum.(eachrow(signal))
    scaled = total./Statistics.mean(total)
    cs = cumsum(scaled)
    ICPduration = runtime[end]
    start = findfirst("On".==timestamps[:,11]) # "Laser State"
    stop = findlast("On".==timestamps[:,11])+1
    from = automatic_datetime(timestamps[1,1]) # "Timestamp"
    to = automatic_datetime(timestamps[end,1])
    LAduration = Millisecond(to - from).value/1000
    lower = 0.0
    if LAduration>ICPduration
        @warn The laser session is longer than the ICP-MS session!
        upper = ICPduration
    else
        upper = ICPduration - LAduration
    end
    misfit = function(lag)
        i1 = argmin(abs.(runtime .- lag))
        i2 = argmin(abs.(runtime .< lag + LAduration))
        log(cs[end]) - log(cs[i2]-cs[i1])
    end
    crude = argmin(misfit.(lower:1.0:upper))
    fit = Optim.optimize(misfit,runtime[crude-1],runtime[crude+1])
    lag = Optim.minimizer(fit)
    if true # change to true to plot the selection window
        p = Plots.plot(runtime,total;label="") # change total to cs for a cumulative plot
        dy = Plots.ylims(p)
        Plots.plot!(p,fill(lag,2),collect(dy[[1,2]]);
                    linecolor="black",linestyle=:solid,label="")
        Plots.plot!(p,fill(lag+LAduration,2),collect(dy[[1,2]]);
                    linecolor="black",linestyle=:solid,label="")
        display(p)
    end
    return lag # TODO
end

function export2IsoplotR(run::Vector{Sample},
                         method::AbstractString,
                         channels::AbstractDict,
                         pars::Union{Pars,NamedTuple},
                         blank::AbstractDataFrame;
                         PAcutoff=nothing,prefix=nothing,
                         fname::AbstractString="PT.json")
    ratios = averat(run,channels,pars,blank;PAcutoff=PAcutoff)
    if isnothing(prefix)
        export2IsoplotR(ratios,method;fname=fname)
    else
        export2IsoplotR(subset(ratios,prefix),method;fname=fname)
    end
end
function export2IsoplotR(ratios::AbstractDataFrame,
                         method::AbstractString;
                         fname::AbstractString="PT.json")
    json = jsonTemplate()

    P, D, d = getPDd(method)

    datastring = "\"ierr\":1,\"data\":{"*
    "\""* P *"/"* D *"\":["*     join(ratios[:,2],",")*"],"*
    "\"err["* P *"/"* D *"]\":["*join(ratios[:,3],",")*"],"*
    "\""* d *"/"* D *"\":["*     join(ratios[:,4],",")*"],"*
    "\"err["* d *"/"* D *"]\":["*join(ratios[:,5],",")*"],"*
    "\"(rho)\":["*join(ratios[:,6],",")*"],"*
    "\"(C)\":[],\"(omit)\":[],"*
    "\"(comment)\":[\""*join(ratios[:,1],"\",\"")*"\"]"

    json = replace(json,"\""*method*"\":{}" =>
                   "\""*method*"\":{"*datastring*"}}")

    
    if method in ["Lu-Hf","Rb-Sr"]
                        
        old = "\"geochronometer\":\"U-Pb\",\"plotdevice\":\"concordia\""
        new = "\"geochronometer\":\""*method*"\",\"plotdevice\":\"isochron\""
        json = replace(json, old => new)
        
        old = "\""*method*"\":{\"format\":1,\"i2i\":true,\"projerr\":false,\"inverse\":false}"
        new = "\""*method*"\":{\"format\":2,\"i2i\":true,\"projerr\":false,\"inverse\":true}"
        json = replace(json, old => new)
        
    end
    
    file = open(fname,"w")
    write(file,json)
    close(file)
    
end
export export2IsoplotR
