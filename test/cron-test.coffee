module.exports = (env) ->

  sinon = env.require 'sinon'
  assert = env.require "assert"

  createDummyParseContext = ->
    variables = {}
    functions = {}
    return context = {
      autocomplete: []
      format: []
      errors: []
      warnings: []
      variables,
      functions
      addHint: ({autocomplete: a, format: f}) ->
      addError: (message) -> @errors.push message
      addWarning: (message) -> @warnings.push message
      hasErrors: -> (@errors.length > 0)
      getErrorsAsString: -> _(@errors).reduce((ms, m) => "#{ms}, #{m}")
      finalize: () -> 
        @autocomplete = _(@autocomplete).uniq().sortBy((s)=>s.toLowerCase()).value()
        @format = _(@format).uniq().sortBy((s)=>s.toLowerCase()).value()
    }

  describe "cron", ->

    plugin = null

    before =>
      @config = {}
      env.CronJob = (
        class DummyCronJob
          constructor: (@options) ->
          start: () -> @startCalled = yes
          stop: () -> @stopCalled = yes
      )
      plugin = (env.require 'pimatic-cron') env

    after =>

    describe 'CronPlugin', =>
      describe "#init()", =>

        it "should register the CronPredicateProvier", =>
          spy = sinon.spy()
          frameworkDummy =
            ruleManager:
              addPredicateProvider: spy
          plugin.init(null, frameworkDummy, @config)
          assert spy.called
          @cronPredProv = spy.getCall(0).args[0]
          assert @cronPredProv?

    describe "CronPredicateProvider", =>
      describe "#getTime()", =>
        it "should return the time", =>
          time = @cronPredProv.getTime()
          assert "Date", typeof time


      tests = [
        predicates: ["its 10am", "10am", "its 10:00"]
        date:
          hour: 10
          minute: 0
          second: 0
          dayOfWeek: undefined
        impliedComponents: [ 'year', 'month', 'day' ]
        cronFormat:
          second: 0
          minute: 0
          hour: 10
          day: "*"
          month: "*"
          dayOfWeek: "*"
        modifier: 'exact'
      ,
        predicates: ["its 10pm", "22:00"]
        date:
          hour: 22
          minute: 0
          second: 0
          dayOfWeek: undefined
        impliedComponents: [ 'year', 'month', 'day' ]
        cronFormat:
          second: 0
          minute: 0
          hour: 22
          day: "*"
          month: "*"
          dayOfWeek: "*"
        modifier: 'exact'
      ,
        predicates: ["its 2am", "2:00"]
        date:
          hour: 2
          minute: 0
          second: 0
          dayOfWeek: undefined
        impliedComponents: [ 'year', 'month', 'day' ]
        cronFormat:
          second: 0
          minute: 0
          hour: 2
          day: "*"
          month: "*"
          dayOfWeek: "*"
        modifier: 'exact'
      ,
        predicates: ["friday"]
        date:
          hour: undefined
          minute: undefined
          second: undefined
          dayOfWeek: 5
        impliedComponents: [ 'year', 'month', 'day' ]
        cronFormat:
          second: 0
          minute: 0
          hour: 0
          day: "*"
          month: "*"
          dayOfWeek: "5"
        modifier: 'exact'
      ,
        predicates: ["friday 9:30"]
        date:
          hour: 9
          minute: 30
          second: 0
          dayOfWeek: 5
        impliedComponents: [ 'year', 'month', 'day' ]
        cronFormat:
          second: 0
          minute: 30
          hour: 9
          day: "*"
          month: "*"
          dayOfWeek: "5"
        modifier: 'exact'
      ,
        predicates: ["its after 10am", "after 10am"]
        date:
          hour: 10
          minute: 0
          second: 0
          dayOfWeek: undefined
        impliedComponents: [ 'year', 'month', 'day' ]
        cronFormat:
          second: 0
          minute: 0
          hour: 10
          day: "*"
          month: "*"
          dayOfWeek: "*"
        modifier: 'after'
      ,
        predicates: ["its before 10am", "before 10am"]
        date:
          hour: 10
          minute: 0
          second: 0
          dayOfWeek: undefined
        impliedComponents: [ 'year', 'month', 'day' ]
        cronFormat:
          second: 0
          minute: 0
          hour: 10
          day: "*"
          month: "*"
          dayOfWeek: "*"
        modifier: 'before'
      ]

      describe '#parseNaturalTextDate()', =>
        createTestNaturalText = (test, pred) =>
          it "should parse #{pred}", =>
            context = createDummyParseContext()
            result = @cronPredProv.parsePredicate(pred, context)
            assert result?
            assert.equal test.modifier, result.predicateHandler.modifier
            test.predHandler = result.predicateHandler
            test.parseResult = result.predicateHandler._reparseDateString(
              result.predicateHandler.dateString
            )
            parseResult = test.parseResult.start
            for name, val of test.date
              assert.equal val, parseResult[name]

            assert parseResult.impliedComponents?
            for ic in test.impliedComponents
              assert ic in parseResult.impliedComponents
            assert test.impliedComponents, parseResult.impliedComponents        
        for test in tests
          for pred in test.predicates
            createTestNaturalText test, pred

      describe '#parseDateToCronFormat()', =>
        createTestCronFormat = (test, pred) =>
          it "should parse #{pred}", =>
            cronFormat = test.predHandler._parseDateToCronFormat test.parseResult.start
            assert.deepEqual test.cronFormat, cronFormat
        for test in tests
          for pred in test.predicates
            createTestCronFormat test, pred

      describe 'CronPredicateHandler', =>
        describe '#on "change"', =>
          that = @
          it "should notify when its 9:00", (finish) ->
            context = createDummyParseContext()
            parseResult = that.cronPredProv.parsePredicate("its 9:00", context)
            predHandler = parseResult.predicateHandler
            assert predHandler?

            predHandler.setup()
            predHandler.once('change', (type) =>
              assert.equal "event", type
              finish()
            )

            assert predHandler.jobs?
            assert predHandler.jobs[0].options?
            assert.equal predHandler.jobs[0].options.cronTime, "0 0 9 * * *"
            assert predHandler.jobs[0].startCalled

            predHandler.jobs[0].options.onTick()

          it "should notify when its after 9:00", (finish) ->
            context = createDummyParseContext()
            parseResult = that.cronPredProv.parsePredicate( "its after 9:00", context)
            predHandler = parseResult.predicateHandler
            assert predHandler?

            predHandler.setup()
            callCount = 0
            predHandler.on('change', (type) =>
              assert typeof type is "boolean"
              callCount++
              if callCount >= 2 then finish()
            )

            assert predHandler.jobs?
            assert predHandler.jobs.length is 2
            assert predHandler.jobs[0].options?
            assert.equal predHandler.jobs[0].options.cronTime, "0 0 9 * * *"
            assert predHandler.jobs[0].startCalled
            assert predHandler.jobs[1].options?
            assert.equal predHandler.jobs[1].options.cronTime, "59 59 23 * * *"
            assert predHandler.jobs[1].startCalled

            predHandler.jobs[0].options.onTick()
            predHandler.jobs[1].options.onTick()

          it "should notify when its before 9:00", (finish) ->
            context = createDummyParseContext()
            parseResult = that.cronPredProv.parsePredicate( "its before 9:00", context)
            predHandler = parseResult.predicateHandler
            assert predHandler?

            predHandler.setup()
            callCount = 0
            predHandler.on('change', (type) =>
              assert typeof type is "boolean"
              callCount++
              if callCount >= 2 then finish()
            )

            assert predHandler.jobs?
            assert predHandler.jobs.length is 2
            assert predHandler.jobs[0].options?
            assert.equal predHandler.jobs[0].options.cronTime, "0 0 0 * * *"
            assert predHandler.jobs[0].startCalled
            assert predHandler.jobs[1].options?
            assert.equal predHandler.jobs[1].options.cronTime, "0 0 9 * * *"
            assert predHandler.jobs[1].startCalled

            predHandler.jobs[0].options.onTick()
            predHandler.jobs[1].options.onTick()

        describe '#getValue()', =>

          testCases = [
            {
              time: new Date(2014, 1, 1, 11)
              predicate: "its 11:00"
              isTrue: yes
            }
            {
              time: new Date(2014, 1, 1, 11)
              predicate: "its 12:00"
              isTrue: no
            }
            {
              time: new Date(2014, 1, 1, 11)
              predicate: "its before 13:00"
              isTrue: yes
            }
            {
              time: new Date(2014, 1, 1, 11)
              predicate: "its before 10:00"
              isTrue: no
            }
            {
              time: new Date(2014, 1, 1, 11)
              predicate: "its after 10:00"
              isTrue: yes
            }
            {
              time: new Date(2014, 1, 1, 11)
              predicate: "its after 13:00"
              isTrue: no
            }
          ]

          that = @

          for tc in testCases
            do(tc) =>
              it "should return #{tc.isTrue} for \"#{tc.predicate}\"", (finish) ->
                that.cronPredProv.getTime = => tc.time
                context = createDummyParseContext()
                parseResult = that.cronPredProv.parsePredicate(tc.predicate, context)
                predHandler = parseResult.predicateHandler
                assert predHandler?

                predHandler.getValue().then( (result) =>
                  assert result is tc.isTrue
                  finish()
                ).catch(finish)





