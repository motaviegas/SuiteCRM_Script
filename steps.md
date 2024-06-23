Steps to follow:

1. Install a lunix server / or use an existing one. This scrit wasa used ina Ubuntur server 24.04
2. Open the terminal and create a sh file, you can give whatever name you want just be sure to have the extension "yourfilename".sh. I use nano
3. change the permissions of the new sh file useing this command
4.   sudo chmod +x yourfilename".sh
5. To run the new script use the following command
6.   sudo ./"yourfilename".sh
7. Follow the script requests and take note of the user & password of the databse that will be requested
8. When the script finishes run the command
9.   sudo mysql_secure_installation
10.     just press enter (there is no root password
11.     Switch to unix_socket authentication [Y/n] Y
12.     Change the root password? [Y/n] y
13.     put your DB root password and take note of it!!!
14.     Remove anonymous users? [Y/n] Y
15.     Disallow root login remotely? [Y/n] Y
16.     Remove test database and access to it? [Y/n] Y
17.     Reload privilege tables now? [Y/n]
18. Now you can use the IP address and conclude the instalation of the CSuite CRM using the DB user and passwords you choose at the begining.

19. On the webpag config on these fields you place
      DATABASE CONFIGURATION:
        SuiteCRM Database User
              USER THAT YOU CHOOSE ON THE SCRIPT
        SuiteCRM Database User Password
              PASSWORD THAT YOU CHOOSE ON THE SCRIPT
        Host Name
              localhost
        Database Name
              CRM

Then the rest you decide which admon user and admin password


    GOOD LUCK!
