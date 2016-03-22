module.exports = (env) ->
  # ##Dependencies
  #  * node.js imports.
  spawn = require("child_process").spawn
  util = require 'util'

  Promise = env.require 'bluebird'
  assert = env.require 'cassert'
  M = env.matcher

  # * `node-chrono` Parses the dates for the `notifyWhen` function.
  chrono = require 'chrono-node'  
  # * `node-cron`: Triggers the time events.
  CronJob = env.CronJob or require('cron').CronJob
  milliseconds = env.require './lib/milliseconds'

  # ##The CronPlugin
  class CronPlugin extends env.plugins.Plugin

    # The `init` function just registers the clock actuator.
    init: (app, @framework, @config) =>
      @framework.ruleManager.addPredicateProvider(new CronPredicateProvider(@framework, @config))
      @framework.ruleManager.addPredicateProvider(new EveryCronPredicateProvider(@framework, @config))

  plugin = new CronPlugin()

  # ##The PredicateProvider
  # Provides the time and time events for the rule module.
  class CronPredicateProvider extends env.predicates.PredicateProvider

    presets: [
      {
        name: "time"
        input: "its 8:00"
      },
      {
        name: "before/after time"
        input: "its after 8:00"
      }
    ]

    constructor: (@framework, @config) ->
      env.logger.info "the time is: #{@getTime()}"
      return 

    getTime: -> new Date()

    parsePredicate: (input, context) ->
      modifier = null
      parseDateResults = null
      dateMatch = null
      dateDetected = no
      dateString = null
      fullMatch = null
      nextInput = null
      exprTokens = null
      theTime = @getTime()

      onDateStringMatch = ( (m, match) => 
        possibleDateString = match.trim() 
        parseDateResults = chrono.parse(possibleDateString, theTime)
        if parseDateResults.length > 0 and parseDateResults[0].index is 0
          dateDetected = yes
          fullMatch = m.getFullMatch()
          dateString = possibleDateString
          nextInput =  m.getRemainingInput()
        return m
      )

      onDateStringExprMatch = ( (m, tokens) =>
        exprTokens = tokens
        dateDetected = yes
        fullMatch = m.getFullMatch()
        nextInput = m.getRemainingInput()
        return m
      )

      hadPrefix = false
      M(input, context)
        .match(
          ['its ', 'it is '], 
          optional: yes, type: 'static', 
          (m, match) => hadPrefix = yes
        )
        .match(
          ['before ', 'after '], 
          param: 'modifier', type: 'select', optional: yes, 
          (m, match) => modifier = match.trim(); hadPrefix = yes
        )
        .or([
          ( (m) => 
            m.match(
              /^(.+?)($| for .*| and .*| or .*|\).*|\].*)/, 
              param: 'time', type: 'time', 
              onDateStringMatch
            ) 
          ), 
          ( (m) => 
            if hadPrefix then m.matchStringWithVars(onDateStringExprMatch) 
            else M(null, context) 
          ),
          ( (m) => 
            if hadPrefix then m.matchVariable( (m, v) => onDateStringExprMatch(m, [v]) )
            else M(null, context)
          )
        ])

      if dateDetected
        if dateString?
          if parseDateResults.length is 0
            context?.addError("Could not parse date: \"#{dateMatch}\"")
            return null
          else if parseDateResults.length > 1
            context?.addError("Multiple dates given: \"#{dateMatch}\"")
            return null
          parseResult = parseDateResults[0]
          if modifier in ['after', 'before'] and parseResult.end?
            context?.addError("You can't give a date range when using \"#{modifier}\"")
          unless modifier?
            if parseResult.end?
              modifier = 'range'
            else
              modifier = 'exact'
        else
          assert Array.isArray exprTokens
          unless modifier?
            modifier = 'exact'

        assert fullMatch?
        assert nextInput?
        return {
          token: fullMatch
          nextInput: nextInput
          predicateHandler: (
            if dateString? then new StringCronPredicateHandler(this, modifier, dateString)
            else new ExprCronPredicateHandler(this, modifier, exprTokens)
          )
        }
      else return null


  class BaseCronPredicateHandler extends env.predicates.PredicateHandler

    constructor: (@provider, @modifier) -> #nop

    _createJobs: (dateString) ->
      parseResult = @_reparseDateString(dateString)
      unless parseResult?
        throw new Error("\"#{dateString}\" is not a valid date or time.")
      {second, minute, hour, day, month, dayOfWeek} = @_parseDateToCronFormat(parseResult.start)
      @jobs = []
      switch @modifier
        when 'exact'
          @jobs.push new CronJob(
            cronTime: "#{second} #{minute} #{hour} #{day} #{month} #{dayOfWeek}"
            onTick: => @emit "change", 'event'
            start: false
          )
        when 'before'
          ###
          before means same day but before the time so the cronjob must trigger at 0:00 
          ###
          @jobs.push new CronJob(
            cronTime: "0 0 0 #{day} #{month} #{dayOfWeek}"
            onTick: => @emit "change", true
            start: false
          )
          # and the predicate gets false at the given time
          @jobs.push new CronJob(
            cronTime: "#{second} #{minute} #{hour} #{day} #{month} #{dayOfWeek}"
            onTick: => @emit "change", false
            start: false
          )
        when 'after'
          # predicate gets true at the given time
          @jobs.push new CronJob(
            cronTime: "#{second} #{minute} #{hour} #{day} #{month} #{dayOfWeek}"
            onTick: => @emit "change", true
            start: false
          )
          # and false at the end of the day
          @jobs.push new CronJob(
            cronTime: "59 59 23 #{day} #{month} #{dayOfWeek}"
            onTick: => @emit "change", false
            start: false
          )
        when 'range'
          # predicate gets true at the given time
          @jobs.push new CronJob(
            cronTime: "#{second} #{minute} #{hour} #{day} #{month} #{dayOfWeek}"
            onTick: => @emit "change", true
            start: false
          )
          # and gets false at the end time
          {second, minute, hour, day, month, dayOfWeek} = @_parseDateToCronFormat(parseResult.end)
          @jobs.push new CronJob(
            cronTime: "#{second} #{minute} #{hour} #{day} #{month} #{dayOfWeek}"
            onTick: => @emit "change", false
            start: false
          )
        else assert false

    _setup: (dateString) -> 
      @_createJobs(dateString)
      job.start() for job in @jobs

    getType: -> if @modifier is 'exact' then 'event' else 'state'

    _reparseDateString: (dateString) ->
      theTime = @provider.getTime()
      return chrono.parse(dateString, theTime)[0]

    _getValue: (dateString)->
      parseResult = @_reparseDateString(dateString)
      unless parseResult?
        throw new Error("\"#{dateString}\" is not a valid date or time.")
      now = parseResult.referenceDate
      start = parseResult.startDate
      end = parseResult.endDate

      unless parseResult.start.hour?
        start.setHours now.getHours()
      unless parseResult.start.minute?
        start.setMinutes now.getMinutes()
      unless parseResult.start.second?
        start.setSeconds now.getSeconds()

      if 'year' in parseResult.start.impliedComponents
        start.setFullYear now.getFullYear()
      if 'month' in parseResult.start.impliedComponents
        start.setMonth now.getMonth()
      if 'day' in parseResult.start.impliedComponents
        start.setDate now.getDate()

      if @modifier is 'exact'
        start.setMilliseconds now.getMilliseconds()

        if parseResult.start.dayOfWeek?
          if parseResult.start.dayOfWeek isnt now.getDay()
            return Promise.resolve(false)

      # console.log "now: ", now
      # console.log "start: ", start
      # console.log "end: ", end

      return Promise.resolve(
        switch @modifier
          when 'exact' then start >= now and start <= now # start == now does not work!
          when 'after' then now >= start
          when 'before' then now <= start
          when 'range' then start <= now <= end
          else assert false
      )

    # Removes the notification for an with `notifyWhen` registered predicate. 
    _destroy: ->
      if @jobs?
        for cj in @jobs
          cj.stop()

    # Convert a parsedDate to a cronjob-syntax like object. The parsedDate must be parsed from 
    # [chrono-node](https://github.com/berryboy/chrono). For Exampe converts the parsedDate of
    # `"12:00"` to:
    # 
    #     {
    #       second: 0
    #       minute: 0
    #       hour: 12
    #       day: "*"
    #       month: "*"
    #       dayOfWeek: "*"
    #     }
    #  
    # or `"Monday"` gets:
    # 
    #     {
    #       second: 0
    #       minute: 0
    #       hour: 0
    #       day: "*"
    #       month: "*"
    #       dayOfWeek: 1
    #     }
    _parseDateToCronFormat: (date) ->
      second = date.second
      minute = date.minute
      hour = date.hour
      #console.log date
      if not second? and not minute? and not hour
        second = 0
        minute = 0
        hour = 0
      else 
        if not second?
          second = "*"
        if not minute?
          minute = "*"
        if not hour?
          hour = "*"

      if date.impliedComponents?
        month = if 'month' in date.impliedComponents then "*" else date.month
        day = if 'day' in date.impliedComponents then "*" else date.day

      dayOfWeek = if date.dayOfWeek? then date.dayOfWeek else "*"
      return {
        second: second
        minute: minute
        hour: hour
        day: day
        month: month
        dayOfWeek: dayOfWeek
      }

  class StringCronPredicateHandler extends BaseCronPredicateHandler

    constructor: (provider, modifier, @dateString) ->
      super(provider, modifier)
      
    setup: -> 
      @_setup(@dateString)
      super()

    destroy: ->
      @_destroy()
      super()
      
    getValue: -> @_getValue(@dateString)

  class ExprCronPredicateHandler extends BaseCronPredicateHandler

    constructor: (provider, modifier, @exprTokens) ->
      super(provider, modifier)
      @_variableManager = @provider.framework.variableManager

    _setupJobs: ->       
      @_variableManager.evaluateStringExpression(@exprTokens).then( (dateString) => 
        if @destroyed then return
        @_setup("#{dateString}")
      ).catch( (error) ->
        env.logger.error("Error creating cron predicate handler: #{error.message}")
        env.logger.debug(error.stack)
      )

    setup: ->
      @destroyed = no
      @_setupJobs()
      @_variableManager.notifyOnChange(@exprTokens, @expChangeListener = () =>
        @_destroy()
        @_setupJobs()
      )
      super()
      
    getValue: -> 
      return @_variableManager.evaluateStringExpression(@exprTokens).then( (dateString) => 
        return @_getValue("#{dateString}")
      )

    destroy: ->
      @_variableManager.cancelNotifyOnChange(@expChangeListener)
      @destroyed = yes
      super()


  # ##The EveryPredicateProvider
  # Provides every x minutes/hours/... predicates.
  class EveryCronPredicateProvider extends env.predicates.PredicateProvider

    constructor: (@framework, @config) ->
      super()

    parsePredicate: (input, context) ->
      exprTokens = null
      fullMatch = null
      nextInput = null
      matchingUnit = null
      M(input, context)
        .match('every ')
        .matchTimeDurationExpression( (m, {tokens, unit}) =>
          exprTokens = tokens
          matchingUnit = unit
          fullMatch = m.getFullMatch()
          nextInput = m.getRemainingInput()
        )

      if fullMatch?
        assert matchingUnit?
        assert exprTokens?
        return {
          token: fullMatch
          nextInput: nextInput
          predicateHandler: new EveryCronPredicateHandler(@framework, exprTokens, matchingUnit)
        }
      else return null


  class EveryCronPredicateHandler extends env.predicates.PredicateHandler

    constructor: (framework, @exprTokens, @unit) ->
      super()
      @_variableManager = framework.variableManager
      
    setup: ->
      @_setupTimeout()
      # change the timeout if the expr changes:
      @_variableManager.notifyOnChange(@exprTokens, @expChangeListener = () =>
        @_lastTime = null
        @_setupTimeout()
      )
      super()

    _setupTimeout: ->
      @destroyed = no
      @_variableManager.evaluateStringExpression(@exprTokens).then( (time) => 
        if @destroyed then return
        timeMs = milliseconds.parse "#{time} #{@unit}"
        now = new Date().getTime()
        unless @_lastTime?
          # aways ececute on full minutes, etc...
          @_lastTime = now - (now % timeMs)
        timeDiff = (@_lastTime + timeMs) - now
        timeDiff = 0 if timeDiff < 0

        clearTimeout(@_timeout)
        @_timeout = setTimeout( ( =>
          @emit "change", 'event'
          @_lastTime += timeMs
          @_setupTimeout()
        ), timeDiff)

      ).catch( (error) ->
        env.logger.error("Error creating cron predicate handler: #{error.message}")
        env.logger.debug(error.stack)
      )
      
    getValue: -> Promise.resolve false
    getType: -> 'event'

    destroy: ->
      if @expChangeListener?
        clearTimeout(@_timeout)
        @_variableManager.cancelNotifyOnChange(@expChangeListener)
        @expChangeListener = null
      @destroyed = yes
      super()

  return plugin
