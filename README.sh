SDMC LAMP
=========
This project sets up a LAMP stack using Docker Compose. It also configures a Drupal 10 site using the current MIramar College repository.

Description
-----------
An in-depth paragraph about your project and overview of use.

Getting Started
---------------
**Dependencies**
1. A bare bones Linux server (Ubuntu 24.04+ recommended)
2. The following packages installed on your server:
   - docker.io
   - docker-compose
   - git
   - curl
   - vim (or your favorite text editor)

**Installing**
1. Clone this project to ~/Desktop.
2. From project root, run ./install.sh
3. Enter MySQL passwords and environment vaeriable when prompted to do so.

Usage
-----
1. Verify container settings (see attached instructions).
2. From project root, run `docker compose up -d` to start the containers.
3. Access the Drupal site at http://dev.loc (or your chosen hostname).
Authors
*William Smith
*Joseph Carlietello
*Assisted by ChatGPT