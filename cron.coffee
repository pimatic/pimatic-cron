module.exports = (env) ->
  # ##Dependencies
  #  * node.js imports.
  spawn = require("child_process").spawn
  util = require 'util'

  # * pimatic imports.
  convict = env.require "convict"
  Q = env.require 'q'
  assert = env.require 'cassert'
  M = env.matcher

  # * `node-chrono` Parses the dates for the `notifyWhen` function.
  chrono = require 'chrono-node'  
  # * `node-cron`: Triggers the time events.
  CronJob = env.CronJob or require('cron').CronJob

  # ##The CronPlugin
  class CronPlugin extends env.plugins.Plugin

    # The `init` function just registers the clock actuator.
    init: (app, @framework, @config) =>
      framework.ruleManager.addPredicateProvider(new CronPredicateProvider config)

  plugin = new CronPlugin

  # ##The PredicateProvider
  # Provides the time and time events for the rule module.
  class CronPredicateProvider extends env.predicates.PredicateProvider
    listener: []

    constructor: (@config) ->
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
      theTime = @getTime()

      M(input, context).match(['its ', 'it is '], optional: yes)
        .match(['before ', 'after '], optional: yes, (m, match) => modifier = match.trim())
        .match(/^(.+?)($| for .*| and .*| or .*|\).*)/, (m, match) => 
          possibleDateString = match.trim() 
          parseDateResults = chrono.parse(possibleDateString, theTime)
          if parseDateResults.length > 0 and parseDateResults[0].index is 0
            dateDetected = yes
            fullMatch = m.getFullMatches()[0]
            dateString = possibleDateString
            nextInput =  m.inputs[0]
        )

      if dateDetected
        assert parseDateResults?
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

        assert fullMatch?
        assert nextInput?
        return {
          token: fullMatch
          nextInput: nextInput
          predicateHandler: new CronPredicateHandler(this, dateString, modifier)
        }
      else return null

  class CronPredicateHandler extends env.predicates.PredicateHandler

    constructor: (@provider, @dateString, @modifier) ->
      parseResult = @reparseDateString()

      {second, minute, hour, day, month, dayOfWeek} = @parseDateToCronFormat(parseResult.start)
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
          {second, minute, hour, day, month, dayOfWeek} = @parseDateToCronFormat(parseResult.end)
          @jobs.push new CronJob(
            cronTime: "#{second} #{minute} #{hour} #{day} #{month} #{dayOfWeek}"
            onTick: => @emit "change", false
            start: false
          )
        else assert false
      job.start() for job in @jobs


    getType: -> if @modifier is 'exact' then 'event' else 'state'


    reparseDateString: ->
      theTime = @provider.getTime()
      return chrono.parse(@dateString, theTime)[0]

    getValue: ->
      parseResult = @reparseDateString()

      now = parseResult.referenceDate
      start = parseResult.startDate
      end = parseResult.endDate

      unless parseResult.start.hour?
        start.setHours now.getHours()
      unless parseResult.start.minute?
        start.setMinutes now.getMinutes()
      unless parseResult.start.second?
        start.setSeconds now.getSeconds()

      if 'day' in parseResult.start.impliedComponents
        start.setDate now.getDate()
      if 'month' in parseResult.start.impliedComponents
        start.setMonth now.getMonth()
      if 'year' in parseResult.start.impliedComponents
        start.setFullYear now.getFullYear()

      if @modifier is 'exact'
        start.setMilliseconds now.getMilliseconds()

        if parseResult.start.dayOfWeek?
          if parseResult.start.dayOfWeek isnt now.getDay()
            return Q(false)

      # console.log "now: ", now
      # console.log "start: ", start
      # console.log "end: ", end

      return Q switch @modifier
        when 'exact' then start >= now and start <= now # start == now does not work!
        when 'after' then now >= start
        when 'before' then now <= start
        when 'range' then start <= now <= end
        else assert false


    # Removes the notification for an with `notifyWhen` registered predicate. 
    destroy: ->
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
    parseDateToCronFormat: (date)->
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

  return plugin