module.exports = (env) ->

  sinon = env.require 'sinon'
  assert = env.require "assert"

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
        predicates: ["its 10am", "10am", "its 10:00", "it is 10:00"]
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
            info = @cronPredProv.parseNaturalTextDate(pred)
            assert info?
            assert.equal test.modifier, info.modifier
            test.parseResult = info.parseResult
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
            cronFormat = @cronPredProv.parseDateToCronFormat test.parseResult.start
            assert.deepEqual test.cronFormat, cronFormat
        for test in tests
          for pred in test.predicates
            createTestCronFormat test, pred

      describe '#notifyWhen()', =>
        that = @
        it "should notify when its 9:00", (finish) ->

          that.cronPredProv.notifyWhen("test1", "its 9:00", (type) =>
            assert.equal "event", type
            finish()
          )

          assert that.cronPredProv.listener["test1"]?
          listener = that.cronPredProv.listener["test1"]
          assert listener.cronjobs?
          assert listener.cronjobs[0].options?
          assert.equal listener.cronjobs[0].options.cronTime, "0 0 9 * * *"
          assert listener.cronjobs[0].startCalled

          listener.cronjobs[0].options.onTick()

        it "should notify when its after 9:00", (finish) ->

          callCount = 0
          that.cronPredProv.notifyWhen("test2", "its after 9:00", (type) =>
            assert typeof type is "boolean"
            callCount++
            if callCount >= 2 then finish()
          )

          assert that.cronPredProv.listener["test2"]?
          listener = that.cronPredProv.listener["test2"]  
          assert listener.cronjobs?
          assert listener.cronjobs.length is 2
          assert listener.cronjobs[0].options?
          assert.equal listener.cronjobs[0].options.cronTime, "0 0 9 * * *"
          assert listener.cronjobs[0].startCalled
          assert listener.cronjobs[1].options?
          assert.equal listener.cronjobs[1].options.cronTime, "59 59 23 * * *"
          assert listener.cronjobs[1].startCalled

          listener.cronjobs[0].options.onTick()
          listener.cronjobs[1].options.onTick()

        it "should notify when its before 9:00", (finish) ->

          callCount = 0
          that.cronPredProv.notifyWhen("test3", "its before 9:00", (type) =>
            assert typeof type is "boolean"
            callCount++
            if callCount >= 2 then finish()
          )

          assert that.cronPredProv.listener["test3"]?
          listener = that.cronPredProv.listener["test3"]  
          assert listener.cronjobs?
          assert listener.cronjobs.length is 2
          assert listener.cronjobs[0].options?
          assert.equal listener.cronjobs[0].options.cronTime, "0 0 0 * * *"
          assert listener.cronjobs[0].startCalled
          assert listener.cronjobs[1].options?
          assert.equal listener.cronjobs[1].options.cronTime, "0 0 9 * * *"
          assert listener.cronjobs[1].startCalled

          listener.cronjobs[0].options.onTick()
          listener.cronjobs[1].options.onTick()

      describe '#isTrue()', =>

        that = @
        it "should return true for its 11:00", (finish) ->
          that.cronPredProv.getTime = => new Date(2014, 1, 1, 11)
          that.cronPredProv.isTrue("test1", "its 11:00").then( (result) =>
            assert result is yes
            finish()
          ).catch(finish)

        it "should return false for its 12:00", (finish) ->
          that.cronPredProv.getTime = => new Date(2014, 1, 1, 11)
          that.cronPredProv.isTrue("test1", "its 12:00").then( (result) =>
            assert result is no
            finish()
          ).catch(finish)

        it "should return true for its before 13:00", (finish) ->
          that.cronPredProv.getTime = => new Date(2014, 1, 1, 11)
          that.cronPredProv.isTrue("test1", "its before 13:00").then( (result) =>
            assert result is yes
            finish()
          ).catch(finish)

        it "should return false for its before 10:00", (finish) ->
          that.cronPredProv.getTime = => new Date(2014, 1, 1, 11)
          that.cronPredProv.isTrue("test1", "its before 10:00").then( (result) =>
            assert result is no
            finish()
          ).catch(finish)

        it "should return true for its after 10:00", (finish) ->
          that.cronPredProv.getTime = => new Date(2014, 1, 1, 11)
          that.cronPredProv.isTrue("test1", "its after 10:00").then( (result) =>
            assert result is yes
            finish()
          ).catch(finish)

        it "should return false for its after 13:00", (finish) ->
          that.cronPredProv.getTime = => new Date(2014, 1, 1, 11)
          that.cronPredProv.isTrue("test1", "its after 13:00").then( (result) =>
            assert result is no
            finish()
          ).catch(finish)



      describe '#cancelNotify()', =>

        it "should cancel notify test1", =>
          @cronPredProv.cancelNotify "test1"
          assert not @cronPredProv.listener["test1"]? 




