using HTTP, JSON3, CSV, DataFrames, Dates, Statistics

"""
Download risk-free rate proxy using short-term Treasury ETF (SHY or BIL).
Returns DataFrame with columns: date, rf (annualized rate as decimal)
"""
function download_risk_free_rate(start_date::Date, token::String)
    # Try SHY (1-3 Year Treasury) first, fallback to BIL (1-3 Month Treasury)
    for ticker in ["SHY", "BIL"]
        try
            @info "Downloading risk-free proxy: $ticker"
            df = download_tiingo_eod(ticker, start_date, token)

            if !isempty(df)
                # Calculate log returns as proxy for rf
                prices = df.adjClose
                log_rets = diff(log.(prices))

                # Annualize returns (252 trading days)
                rf_df = DataFrame(
                    date = df.date[2:end],
                    rf = log_rets * 252.0
                )

                @info "Using $ticker as risk-free rate proxy"
                return rf_df
            end
        catch e
            @warn "Failed to download $ticker: $e"
        end
    end

    @warn "Could not download risk-free proxy. Using rf=0."
    return DataFrame(date = [start_date], rf = [0.0])
end

"""
Download EOD adjusted close data from Tiingo API.
"""
function download_tiingo_eod(ticker::String, start_date::Date, token::String)
    url = "https://api.tiingo.com/tiingo/daily/$(ticker)/prices"
    params = Dict(
        "startDate" => string(start_date),
        "token" => token
    )

    try
        response = HTTP.get(url, query=params)
        data = JSON3.read(String(response.body))

        # Parse dates (format: "2020-01-02T00:00:00.000Z")
        dates = [Date(split(string(d), "T")[1]) for d in getproperty.(data, :date)]

        df = DataFrame(
            date = dates,
            ticker = fill(ticker, length(data)),
            adjClose = Float64.(getproperty.(data, :adjClose))
        )
        return df
    catch e
        @warn "Failed to download $ticker: $e"
        return DataFrame()
    end
end

"""
Download data for multiple tickers and align by common dates.
"""
function download_universe(tickers::Vector{String}, start_date::Date, token::String)
    @info "Downloading data for $(length(tickers)) tickers from Tiingo..."

    all_data = DataFrame[]
    for ticker in tickers
        df = download_tiingo_eod(ticker, start_date, token)
        if !isempty(df)
            push!(all_data, df)
        end
    end

    if isempty(all_data)
        error("No data downloaded. Check your TIINGO_TOKEN and internet connection.")
    end

    # Combine and pivot to wide format
    combined = vcat(all_data...)
    wide_df = unstack(combined, :date, :ticker, :adjClose)
    sort!(wide_df, :date)

    return wide_df
end

"""
Calculate log returns and perform basic quality control.
"""
function calculate_returns(prices_df::DataFrame; qc_threshold::Float64=0.5)
    dates = prices_df.date
    tickers = names(prices_df)[2:end]  # exclude 'date' column

    n_assets = length(tickers)
    n_dates = nrow(prices_df)

    # Calculate log returns
    returns = DataFrame(date = dates[2:end])

    for ticker in tickers
        prices = prices_df[!, ticker]
        log_rets = diff(log.(prices))
        returns[!, ticker] = log_rets
    end

    # Quality control: remove obvious errors (|r| > qc_threshold followed by symmetric reversal)
    for ticker in tickers
        rets = returns[!, ticker]
        for i in 1:(length(rets)-1)
            if !ismissing(rets[i]) && !ismissing(rets[i+1])
                if abs(rets[i]) > qc_threshold && abs(rets[i+1]) > qc_threshold
                    if abs(rets[i] + rets[i+1]) < 0.01  # symmetric reversal
                        @info "QC: Removing outliers in $ticker at position $i and $(i+1)"
                        rets[i] = missing
                        rets[i+1] = missing
                    end
                end
            end
        end
        returns[!, ticker] = rets
    end

    return returns
end

"""
Filter tickers by minimum history requirement.
"""
function filter_by_history(prices_df::DataFrame, min_years::Int=15; min_assets::Int=8)
    last_date = maximum(prices_df.date)
    cutoff_date = last_date - Year(min_years)

    tickers = names(prices_df)[2:end]
    valid_tickers = String[]

    @info "Filtering tickers with at least $min_years years of history (cutoff: $cutoff_date)..."

    for ticker in tickers
        prices = prices_df[!, ticker]
        valid_idx = findall(!ismissing, prices)

        if isempty(valid_idx)
            @info "Removed $ticker: no valid data"
            continue
        end

        first_date = prices_df.date[first(valid_idx)]
        n_valid = length(valid_idx)

        if first_date <= cutoff_date && n_valid >= min_years * 252
            push!(valid_tickers, ticker)
        else
            @info "Removed $ticker: insufficient history (first: $first_date, n=$n_valid)"
        end
    end

    if length(valid_tickers) < min_assets
        error("Only $(length(valid_tickers)) assets passed the $(min_years)y filter. " *
              "Please reduce min_history_years or expand the candidate list.")
    end

    @info "$(length(valid_tickers)) assets passed the filter: $valid_tickers"

    # Return filtered dataframe
    cols_to_keep = vcat([:date], Symbol.(valid_tickers))
    return select(prices_df, cols_to_keep)
end

"""
Load and prepare data: download, filter, compute returns.
"""
function load_data(;
    tickers::Vector{String} = ["SPY", "IWD", "IWF", "VTV", "VUG",
                                 "EFA", "EEM",
                                 "TLT", "IEF", "LQD", "HYG", "EMB",
                                 "VNQ", "GLD", "DBC", "TIP"],
    start_date::Date = Date(2002, 1, 1),
    min_years::Int = 15,
    qc_threshold::Float64 = 0.5,
    min_assets::Int = 8,
    kwargs...
)
    # Get token from environment
    token = get(ENV, "TIINGO_TOKEN", "")
    if isempty(token)
        error("TIINGO_TOKEN not found in environment. Please set it before running.")
    end

    # Download data
    prices_df = download_universe(tickers, start_date, token)

    # Filter by history
    filtered_prices = filter_by_history(prices_df, min_years, min_assets=min_assets)

    # Calculate returns
    returns_df = calculate_returns(filtered_prices, qc_threshold=qc_threshold)

    # Remove rows with any missing values (intersection of valid dates)
    returns_clean = dropmissing(returns_df)

    @info "Final dataset: $(nrow(returns_clean)) days × $(ncol(returns_clean)-1) assets"
    @info "Date range: $(minimum(returns_clean.date)) to $(maximum(returns_clean.date))"

    return returns_clean, filtered_prices
end
