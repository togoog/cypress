require("../../spec_helper")

resolve = require('resolve')
EE = require("events")
Fixtures = require("../../support/helpers/fixtures")
path = require("path")
appData = require("#{root}../lib/util/app_data")
savedState = require("#{root}../lib/saved_state")

plugins = require("#{root}../lib/plugins")
preprocessor = require("#{root}../lib/plugins/preprocessor")

describe "lib/plugins/preprocessor", ->
  beforeEach ->
    Fixtures.scaffold()
    @todosPath = Fixtures.projectPath("todos")

    @filePath = "path/to/test.coffee"
    @fullFilePath = path.join(@todosPath, @filePath)
    @integrationFolder = '/integration-path/'

    @testPath = path.join(@todosPath, "test.coffee")
    @localPreprocessorPath = path.join(@todosPath, "prep.coffee")

    @plugin = sinon.stub().returns("/path/to/output.js")
    plugins.register("file:preprocessor", @plugin)

    preprocessor.close()

    @config = {
      preprocessor: "custom"
      projectRoot: @todosPath
    }

  context "#getFile", ->
    it "executes the plugin with file path", ->
      preprocessor.getFile(@filePath, @config)
      expect(@plugin).to.be.called
      expect(@plugin.lastCall.args[0].filePath).to.equal(@fullFilePath)

    it "executes the plugin with output path", ->
      preprocessor.getFile(@filePath, @config)
      expectedPath = appData.projectsPath(savedState.toHashName(@todosPath), "bundles", @filePath)
      expect(@plugin.lastCall.args[0].outputPath).to.equal(expectedPath)

    it "executes the plugin with output path when integrationFolder was defined", ->
      preprocessor.getFile(@integrationFolder + @filePath, Object.assign({integrationFolder: @integrationFolder}, @config))
      expectedPath = appData.projectsPath(savedState.toHashName(@todosPath), "bundles", @filePath)
      expect(@plugin.lastCall.args[0].outputPath).to.equal(expectedPath)

    it "returns a promise resolved with the plugin's outputPath", ->
      preprocessor.getFile(@filePath, @config).then (filePath) ->
        expect(filePath).to.equal("/path/to/output.js")

    it "emits 'file:updated' with filePath when 'rerun' is emitted", ->
      fileUpdated = sinon.spy()
      preprocessor.emitter.on("file:updated", fileUpdated)
      preprocessor.getFile(@filePath, @config)
      @plugin.lastCall.args[0].emit("rerun")
      expect(fileUpdated).to.be.calledWith(@fullFilePath)

    it "invokes plugin again when isTextTerminal: false", ->
      @config.isTextTerminal = false
      preprocessor.getFile(@filePath, @config)
      preprocessor.getFile(@filePath, @config)
      expect(@plugin).to.be.calledTwice

    it "does not invoke plugin again when isTextTerminal: true", ->
      @config.isTextTerminal = true
      preprocessor.getFile(@filePath, @config)
      preprocessor.getFile(@filePath, @config)
      expect(@plugin).to.be.calledOnce

    it "uses default preprocessor if none registered", ->
      plugins._reset()
      sinon.stub(plugins, "register")
      sinon.stub(plugins, "execute").returns(->)
      browserifyFn = ->
      browserify = sinon.stub().returns(browserifyFn)
      ## mock default options
      browserify.defaultOptions = {
        browserifyOptions: {
          extensions: [],
          transform: [
            [],
            ['babelify', {
              presets: [],
              extensions: [],
            }]
          ]
        }
      }
      mockery.registerMock("@cypress/browserify-preprocessor", browserify)
      preprocessor.getFile(@filePath, @config)
      expect(plugins.register).to.be.calledWith("file:preprocessor", browserifyFn)
      expect(browserify).to.be.called

  context "#removeFile", ->
    it "emits 'close'", ->
      preprocessor.getFile(@filePath, @config)
      onClose = sinon.spy()
      @plugin.lastCall.args[0].on("close", onClose)
      preprocessor.removeFile(@filePath, @config)
      expect(onClose).to.be.called

    it "emits 'close' with file path on base emitter", ->
      onClose = sinon.spy()
      preprocessor.emitter.on("close", onClose)
      preprocessor.getFile(@filePath, @config)
      preprocessor.removeFile(@filePath, @config)
      expect(onClose).to.be.calledWith(@fullFilePath)

  context "#close", ->
    it "emits 'close' on config emitter", ->
      preprocessor.getFile(@filePath, @config)
      onClose = sinon.spy()
      @plugin.lastCall.args[0].on("close", onClose)
      preprocessor.close()
      expect(onClose).to.be.called

    it "emits 'close' on base emitter", ->
      onClose = sinon.spy()
      preprocessor.emitter.on "close", onClose
      preprocessor.getFile(@filePath, @config)
      preprocessor.close()
      expect(onClose).to.be.called

  context "#clientSideError", ->
    beforeEach ->
      sinon.stub(console, "error") ## keep noise out of console

    it "send javascript string with the error", ->
      expect(preprocessor.clientSideError("an error")).to.equal("""
      (function () {
        Cypress.action("spec:script:error", {
          type: "BUNDLE_ERROR",
          error: "an error"
        })
      }())
      """)


    it "does not replace new lines with {newline} placeholder", ->
      expect(preprocessor.clientSideError("with\nnew\nlines")).to.include('error: "with\\nnew\\nlines"')

    it "does not remove command line syntax highlighting characters", ->
      expect(preprocessor.clientSideError("[30mfoo[100mbar[7mbaz")).to.include('error: "[30mfoo[100mbar[7mbaz"')

  context "#errorMessage", ->
    it "handles error strings", ->
      expect(preprocessor.errorMessage("error string")).to.include("error string")

    it "handles standard error objects and sends the stack", ->
      err = new Error()
      err.stack = "error object stack"

      expect(preprocessor.errorMessage(err)).to.equal("error object stack")

    it "sends err.annotated if stack is not present", ->
      err = {
        stack: undefined
        annotated: "annotation"
      }

      expect(preprocessor.errorMessage(err)).to.equal("annotation")

    it "sends err.message if stack and annotated are not present", ->
      err = {
        stack: undefined
        message: "message"
      }

      expect(preprocessor.errorMessage(err)).to.equal("message")

    it "removes stack lines", ->
      expect(preprocessor.errorMessage("foo\n  at what.ever (foo 23:30)\n baz\n    at where.ever (bar 1:5)")).to.equal("foo\n baz")

  context "#setDefaultPreprocessor", ->
    it "finds TypeScript in the project root", ->
      mockPlugin = {}
      sinon.stub(plugins, "register")
      sinon.stub(preprocessor, "createBrowserifyPreprocessor").returns(mockPlugin)

      preprocessor.setDefaultPreprocessor(@config)

      expect(plugins.register).to.be.calledWithExactly("file:preprocessor", mockPlugin)
      # in this mock project, the TypeScript should be found
      # from the monorepo
      monorepoRoot = path.join(__dirname, "../../../../..")
      typescript = resolve.sync("typescript", {
        basedir: monorepoRoot
      })
      expect(preprocessor.createBrowserifyPreprocessor).to.be.calledWith({ typescript })

    it "does not have typescript if not found", ->
      mockPlugin = {}
      sinon.stub(plugins, "register")
      sinon.stub(preprocessor, "createBrowserifyPreprocessor").returns(mockPlugin)
      sinon.stub(resolve, "sync")
        .withArgs("typescript", { basedir: @todosPath })
        .throws(new Error('TypeScript not found'))

      preprocessor.setDefaultPreprocessor(@config)

      expect(plugins.register).to.be.calledWithExactly("file:preprocessor", mockPlugin)
      expect(preprocessor.createBrowserifyPreprocessor).to.be.calledWith({ typescript: null })
