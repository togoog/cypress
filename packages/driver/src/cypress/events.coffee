# _ = require("lodash")
# Backbone = require("backbone")

## adds a custom lightweight event bus
## to the Cypress class

# splice = (index) ->
  # @_events.splice(index, 1)

_ = require("lodash")
EE = require("eventemitter2")
log = require("debug")("cypress:driver")
Promise = require("bluebird")

proxyFunctions = "emit emitThen emitMap".split(" ")

withoutFunctions = (arr) ->
  _.reject(arr, _.isFunction)

logEmit = true

module.exports = {
  extend: (obj) ->
    events = new EE

    events.setMaxListeners(Infinity)

    events.proxyTo = (child) ->
      parent = obj

      for fn in proxyFunctions
        ## create a closure
        do (fn) ->
          original = parent[fn]

          ## whenever our parent parent are emitting
          ## proxy those to the child obj
          parent[fn] = ->
            ret1 = original.apply(parent, arguments)

            ## dont let our child emits also log
            logEmit = false

            ret2 = child[fn].apply(child, arguments)

            logEmit = true

            ## aggregate the results of the parent
            ## and child
            switch fn
              when "emit"
                ## boolean
                ret1 or ret2
              when "emitMap"
                ## array of results
                ret1.concat(ret2)
              when "emitThen"
                Promise.join ret1, ret2, (a, a2) ->
                  ## array of results
                  a.concat(a2)

      return null

    events.emitMap = (eventName, args...) ->
      listeners = obj.listeners(eventName)

      ## is our log enabled and have we not silenced
      ## this specific object?
      if log.enabled and logEmit
        log("emitted: '%s' to '%d' listeners - with args: %o", eventName, listeners.length, args...)

      listener = (fn) ->
        fn.apply(obj, args)

      ## collect the results from the listeners
      _.map(listeners, listener)

    events.emitThen = (eventName, args...) ->
      listeners = obj.listeners(eventName)

      ## is our log enabled and have we not silenced
      ## this specific object?
      if log.enabled and logEmit
        log("emitted: '%s' to '%d' listeners - with args: %o", eventName, listeners.length, args...)

      listener = (fn) ->
        fn.apply(obj, args)

      Promise.map(listeners, listener)

    ## is our log enabled and have we not silenced
    ## this specific object?
    if log.enabled
      emit = events.emit

      events.emit = (eventName, args...) ->
        ret = emit.apply(obj, [eventName].concat(args))

        ## bail early if we have turned
        ## off logging temporarily
        if logEmit is false
          return ret

        if args.length
          log("emitted: '%s' - with args: %o", eventName, withoutFunctions(args)...)
        else
          log("emitted: '%s'", eventName)

        return ret

    _.extend(obj, events)

    ## return the events object
    return events
}
  # $Cypress.extend
  #   event: (name) ->
  #     return if not @_events
  #
  #     _.map @_events[name], "callback"
  #
  #   invoke: (name, args...) ->
  #     return if not events = @event(name)
  #
  #     _.map events, (event) =>
  #       event.apply(@cy, args)
  #
  #   ## coerce the context of trigger'd events
  #   ## to ALWAYS be @cy
  #   trigger: (name) ->
  #     return if not events = @_events and @_events[name]
  #
  #     for event in events
  #       event.ctx = @cy
  #
  #     Backbone.Events.trigger.apply(@, arguments)
  #
  #   triggerPromise: (args...) ->
  #     new Promise (resolve, reject) =>
  #
  #       cb = (resp) ->
  #         if _.has(resp, "__error")
  #           e = resp.__error
  #
  #           if _.isString(e)
  #             err = new Error(e)
  #           else
  #             err = new Error(e.message)
  #
  #             for own prop, val of e
  #               err[prop] = val
  #
  #           err.triggerPromise = true
  #
  #           reject(err)
  #         else
  #           resolve(resp)
  #
  #       args.push(cb)
  #
  #       @trigger.apply(@, args)
  #     .cancellable()
