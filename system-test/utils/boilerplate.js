// Copyright (c) Jupyter Development Team.
// Distributed under the terms of the Modified BSD License.
var Promise = require('bluebird');
var wd = require('wd');
require('colors');
var chai = require('chai');
var chaiAsPromised = require('chai-as-promised');
var parseArgs = require('minimist');

//  Parse the args
var args = parseArgs(process.argv);
args.local = args['test-type'] === 'local';
var remote = !args.local;
args.server = args.server || (remote ? 'ondemand.saucelabs.com' : 'localhost:4444');

//  Setup chai
chai.use(chaiAsPromised);
chai.should();
chaiAsPromised.transferPromiseness = wd.transferPromiseness;

// tagging chai assertion errors for retry
var tagChaiAssertionError = function(err) {
    // throw error and tag as retriable to poll again
    err.retriable = err instanceof chai.AssertionError;
    throw err;
};

// Configure webdriver
wd.configureHttp({
    timeout: 60000,
    retryDelay: 15000,
    retries: 5,
    baseUrl: args.baseurl
});

//  The browser capabilities we would like setup by selenium
var desired = {browserName: 'chrome', platform: 'OS X 10.10'};
desired.platform = args.platform || desired.platform;
desired.browserName = args.browser || desired.browserName;
desired.tags = ['widgets', 'system-test', desired.browserName];
// If there is a build number, include it in the desired attributes for sauce labs
if (process.env.TRAVIS_JOB_NUMBER) {
  desired.tunnelIdentifier = process.env.TRAVIS_JOB_NUMBER;
  desired.build = 'widgets-build-' + process.env.TRAVIS_JOB_NUMBER;
}

//  The selenium test server, local or remote, we will be using to test against
var testServer = 'http://' + args.server + '/wd/hub';
if (remote) {
  testServer = 'http://' + process.env.SAUCE_USERNAME + ':' + process.env.SAUCE_ACCESS_KEY + '@' + args.server + '/wd/hub';
}

console.log('Test server is ', args.server);
console.log('Travis job number is: ', process.env.TRAVIS_JOB_NUMBER);
console.log('Sauce user name is defined? ', !!process.env.SAUCE_USERNAME);
console.log('Sauce access key is defined? ', !!process.env.SAUCE_ACCESS_KEY);

/**
  * A helper class to setup webdriver, create a browser, and widget objects for
  * use within the system tests.
  */
var Boilerplate = function(){
  this.browser = wd.promiseChainRemote(testServer);
  this.allPassed = true;
};

/**
  * Setups the before and after calls for each of your tests. The boilerplate
  * will start each test on startingURL, which is a relative path to the resource to load.
  */
Boilerplate.prototype.setup = function(testName, startingURL, outputCount){
  var that = this;

  var outputAsserter = new wd.Asserter(
    function(target) { // browser or el
      return target
        .elementsByCssSelector('div.output_area').then(function(nodes) {
            console.log("output areas visible: ", nodes.length, "/", outputCount)
            nodes.should.have.length.above(outputCount-1);
            return target; // this will be returned by waitFor
            // and ignored by waitForElement.
        })
        .catch(tagChaiAssertionError); // tag errors for retry in catch.
    }
  );

  before(function(done){
    if (args.verbose) {
        // optional logging
        this.browser.on('status', function(info) {
            console.log(info.cyan);
        });
        this.browser.on('command', function(meth, path, data) {
            console.log(' > ' + meth.yellow, path.grey, data || '');
        });
    }

    desired.name = testName ? 'Urth Widgets System Test - ' + testName
        : 'Urth Widgets System Test';

    var kernelStartTimeout = 200000;
    var defaultTimeout = 10000;
    var runAllCompletionTimeout = 50000;

    function clickTheElement(element) {
        return new Promise(function(resolve) {
            var newElement = element.click()
                      .elementByLinkText("<", "Cell")
                      .click()
                      .waitForElementByLinkText("Run Cells", wd.asserters.isDisplayed, 10000)
                      .elementByLinkText("Run Cells")
                      .click()
                      .sleep(5000);
            resolve(newElement);
        });
    }

    function runAllCells(elements, idx) {
        if (idx > elements.length - 1) {
            return;
        }

        var element = elements[idx];
        clickTheElement(element).then(function(elem) {
            console.log("running cell: ", idx);
            runAllCells(elements, idx+1);
        })
    }

    this.browser.init(desired)
        .get(startingURL || '/')
        .waitForElementByCssSelector("#kernel_indicator_icon.kernel_idle_icon", wd.asserters.isDisplayed, kernelStartTimeout)
        .elementsByCssSelector('div.input').then(function (elements) {
            runAllCells(elements, 0);
        })
        .waitFor(outputAsserter, runAllCompletionTimeout*5, 1000)
        .eval("!!document.body.createShadowRoot", function(err, value) {
            this.browserSupportsShadowDOM = value;
        }.bind(this))
        .nodeify(done);
  }.bind(this));

  after(function(done){
    var result = this.browser.quit();
    if (remote) {
      result = result.sauceJobStatus(this.allPassed);
    }
    result.nodeify(done);
  }.bind(this));

  afterEach(function(done) {
    that.allPassed = that.allPassed && (this.currentTest.state === 'passed');
    done();
  });
};

module.exports = Boilerplate;
