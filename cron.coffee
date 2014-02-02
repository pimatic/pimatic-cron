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

  # * `node-time`: Extend the global Date object to include the `setTimezone` and `getTimezone`.
  time = require('time')(Date)
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

    getTime: () -> 
      now = new Date
      now.setTimezone @config.timezone
      return now

    canDecide: (predicate, context) ->
      info = @parseNaturalTextDate predicate, context
      return ( 
        if info? 
          if info.modifier is 'exact' then 'event'
          else yes
        else no
      )

    # Returns `true` if the given predicate string is considert to be true. For example the 
    # predicate `"Sep 12"` is considert to be true if it is the 12th of october, 2013 from 0 to 
    # 23.59 o'clock. If the given predicate is not an valid date string an Error is thrown. 
    isTrue: (id, predicate) ->
      info = @parseNaturalTextDate predicate
      if info?
        now = info.parseResult.referenceDate
        start = info.parseResult.startDate
        end = info.parseResult.endDate
        #console.log "now: ", now
        #console.log "start: ", start
        #console.log "end: ", end

        return Q switch info.modifier
          when 'exact' then start is now
          when 'after' then now >= start
          when 'before' then now <= start
          else assert false
        
      else
        throw new Error "Clock sensor can not decide \"#{predicate}\"!"

    # Removes the notification for an with `notifyWhen` registered predicate. 
    cancelNotify: (id) ->
      if @listener[id]?
        for cj in @listener[id].cronjobs
          cj.stop()
        delete @listener[id]

    # Registers notification for time events. 
    notifyWhen: (id, predicate, callback) ->
      info = @parseNaturalTextDate(predicate)
      if info?
        {second, minute, hour, day, month, dayOfWeek} = @parseDateToCronFormat(
          info.parseResult.start
        )
        jobs = []
        switch info.modifier
          when 'exact'
            jobs.push new CronJob(
              cronTime: "#{second} #{minute} #{hour} #{day} #{month} #{dayOfWeek}"
              onTick: => callback('event')
              start: false
              timezone: @config.timezone
            )
          when 'before'
            ###
            before means same day but before the time so the cronjob must trigger at 0:00 
            ###
            jobs.push new CronJob(
              cronTime: "0 0 0 #{day} #{month} #{dayOfWeek}"
              onTick: => callback(true)
              start: false
              timezone: @config.timezone
            )
            # and the predicate gets false at the given time
            jobs.push new CronJob(
              cronTime: "#{second} #{minute} #{hour} #{day} #{month} #{dayOfWeek}"
              onTick: => callback(false)
              start: false
              timezone: @config.timezone
            )
          when 'after'
            # predicate gets true at the given time
            jobs.push new CronJob(
              cronTime: "#{second} #{minute} #{hour} #{day} #{month} #{dayOfWeek}"
              onTick: => callback(true)
              start: false
              timezone: @config.timezone
            )
            # and false at the end of the day
            jobs.push new CronJob(
              cronTime: "59 59 23 #{day} #{month} #{dayOfWeek}"
              onTick: => callback(false)
              start: false
              timezone: @config.timezone
            )
          else assert false
        @listener[id] = 
          id: id
          cronjobs: jobs
          modifier: info.modifier
        job.start() for job in jobs
      else throw new Error "Clock sensor can not decide \"#{predicate}\"!"

    # Take a date as string in natural language and parse it with 
    # [chrono-node](https://github.com/berryboy/chrono).
    # For example transforms:
    # `"Sep 12-13"`
    # to:
    # 
    #     { start: 
    #       { year: 2013,
    #         month: 8,
    #         day: 12,
    #         isCertain: [Function],
    #         impliedComponents: [Object],
    #         date: [Function] },
    #      startDate: Thu Sep 12 2013 12:00:00 GMT+0900 (JST),
    #      end: 
    #       { year: 2013,
    #         month: 8,
    #         day: 13,
    #         impliedComponents: [Object],
    #         isCertain: [Function],
    #         date: [Function] },
    #      endDate: Fri Sep 13 2013 12:00:00 GMT+0900 (JST),
    #      referenceDate: Sat Aug 17 2013 17:54:57 GMT+0900 (JST),
    #      index: 0,
    #      text: 'Sep 12-13',
    #      concordance: 'Sep 12-13' }
    parseNaturalTextDate: (naturalTextDate, context)->
      modifier = null
      parseDateResults = null
      dataMatch = null
      ended = no

      matchDate = (m) => m.match(/^(.+)()$/, (m, match) => 
        dataMatch = match.trim()
        parseDateResults = chrono.parse(dataMatch, @getTime())
        m.onEnd( => ended = yes)
      )

      m = M(naturalTextDate, context).match(['its', 'it is'])
      matchDate(m)
      m = m.match([' before ', ' after '], (m, match) => modifier = match.trim())
      matchDate(m)

      if ended
        assert parseDateResults?
        if parseDateResults.length is 0
          context?.addError("Could not parse date: \"#{dataMatch}\"")
          return null
        else if parseDateResults.length > 1
          context?.addError("Multiple dates given: \"#{dataMatch}\"")
          return null
        parseResult = parseDateResults[0]
        unless modifier?
          if parseResult.end?
            modifier = 'between'
          else
            modifier = 'exact'
        return {
          parseResult: parseResult
          modifier: modifier
        }
      else return null

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