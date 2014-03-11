module.exports = (grunt) ->
  grunt.initConfig
    pkg: grunt.file.readJSON "package.json"
    coffee:
      files:
        expand: true
        #cwd: "./"
        src: ["./*.coffee"]
        dest: "."
        ext: ".js"
      

  grunt.loadNpmTasks "grunt-contrib-coffee"
  
  grunt.registerTask "default", ["coffee"]