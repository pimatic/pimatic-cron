module.exports = (env) ->

  sinon = env.require 'sinon'
  assert = env.require "assert"

  describe "cron", ->

    plugin = (env.require 'pimatic-cron') env

    before =>
      @config = {}
      @clock = sinon.useFakeTimers()

    after =>
      @clock.restore()

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
      ]

      describe '#parseNaturalTextDate()', =>
        createTestNaturalText = (test, pred) =>
          it "should parse #{pred}", =>
            test.parsedDate = @cronPredProv.parseNaturalTextDate(pred)
            parsedDate = test.parsedDate.start
            for name, val of test.date
              assert.equal val, parsedDate[name]

            assert parsedDate.impliedComponents?
            for ic in test.impliedComponents
              assert ic in parsedDate.impliedComponents
            assert test.impliedComponents, parsedDate.impliedComponents        
        for test in tests
          for pred in test.predicates
            createTestNaturalText test, pred

      describe '#parseDateToCronFormat()', =>
        createTestCronFormat = (test, pred) =>
          it "should parse #{pred}", =>
            cronFormat = @cronPredProv.parseDateToCronFormat test.parsedDate
            assert.deepEqual test.cronFormat, cronFormat
        for test in tests
          for pred in test.predicates
            createTestCronFormat test, pred

      describe '#notifyWhen()', =>
        that = @
        it "should notify when its 9:00", (finish) ->
          this.timeout(0)

          that.cronPredProv.notifyWhen("test1", "its 9:00", (type) =>
            assert.equal "event", type
            finish()
          )

          that.clock.tick(60*60*1000*9)

      describe '#cancelNotify()', =>

        it "should cancel notify test1", =>
          @cronPredProv.cancelNotify "test1"
          assert not @cronPredProv.listener["test1"]?
          @clock.tick(60*60*1000*48)




