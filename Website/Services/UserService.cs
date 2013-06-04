using System;
using System.Collections.Generic;
using System.Data.Entity;
using System.Linq;

namespace NuGetGallery
{
    public class UserService : IUserService
    {
        public ICryptographyService Crypto { get; protected set; }
        public IConfiguration Config { get; protected set; }
        public IEntityRepository<User> UserRepository { get; protected set; }
        readonly ILdapService ldapService;

        protected UserService() {}

        //public UserService(
        //    IConfiguration config,
        //    ICryptographyService crypto,
        //    IEntityRepository<User> userRepository) : this()
        //{
        //    Config = config;
        //    Crypto = crypto;
        //    UserRepository = userRepository;
        //}

       public UserService(
           IConfiguration config,
           ICryptographyService crypto,
           IEntityRepository<User> userRepository,
           ILdapService ldapService)            : this()
        {
            Config = config;
            Crypto = crypto;
            UserRepository = userRepository;
            this.ldapService = ldapService;
        }
        public virtual User Create(
            string username,
            string password,
            string emailAddress)
        {
            // TODO: validate input
            // TODO: consider encrypting email address with a public key, and having the background process that send messages have the private key to decrypt

            var existingUser = FindByUsername(username);
            if (existingUser != null)
            {
                throw new EntityException(Strings.UsernameNotAvailable, username);
            }

            existingUser = FindByEmailAddress(emailAddress);
            if (existingUser != null)
            {
                throw new EntityException(Strings.EmailAddressBeingUsed, emailAddress);
            }

            var hashedPassword = Crypto.GenerateSaltedHash(password, Constants.PBKDF2HashAlgorithmId);

            var newUser = new User(
                username,
                hashedPassword)
                {
                    ApiKey = Guid.NewGuid(),
                    EmailAllowed = true,
                    UnconfirmedEmailAddress = emailAddress,
                    EmailConfirmationToken = Crypto.GenerateToken(),
                    PasswordHashAlgorithm = Constants.PBKDF2HashAlgorithmId,
                };

            if (!Config.ConfirmEmailAddresses)
            {
                newUser.ConfirmEmailAddress();
            }

            UserRepository.InsertOnCommit(newUser);
            UserRepository.CommitChanges();

            return newUser;
        }

        public void UpdateProfile(User user, string emailAddress, bool emailAllowed)
        {
            if (user == null)
            {
                throw new ArgumentNullException("user");
            }

            if (emailAddress != user.EmailAddress)
            {
                var existingUser = FindByEmailAddress(emailAddress);
                if (existingUser != null && existingUser.Key != user.Key)
                {
                    throw new EntityException(Strings.EmailAddressBeingUsed, emailAddress);
                }
                user.UnconfirmedEmailAddress = emailAddress;
                user.EmailConfirmationToken = Crypto.GenerateToken();
            }

            user.EmailAllowed = emailAllowed;
            UserRepository.CommitChanges();
        }

        public User FindByApiKey(Guid apiKey)
        {
            return UserRepository.GetAll().SingleOrDefault(u => u.ApiKey == apiKey);
        }

        public virtual User FindByEmailAddress(string emailAddress)
        {
            // TODO: validate input

            return UserRepository.GetAll().SingleOrDefault(u => u.EmailAddress == emailAddress);
        }

        public virtual User FindByUnconfirmedEmailAddress(string unconfirmedEmailAddress)
        {
            // TODO: validate input
            //modified by fwang5: avoid found more one records
            //return UserRepository.GetAll().SingleOrDefault(u => u.UnconfirmedEmailAddress == unconfirmedEmailAddress);
            return UserRepository.GetAll().FirstOrDefault(u => u.UnconfirmedEmailAddress == unconfirmedEmailAddress);
        }

        public IQueryable<User> FindByUnconfirmedEmailAddressList(string unconfirmedEmailAddress,String emailConfirmationToken)
        {
            return UserRepository.GetAll().Where(u => (u.UnconfirmedEmailAddress == unconfirmedEmailAddress && u.EmailConfirmationToken != emailConfirmationToken));
        }

        public virtual User FindByUsername(string username)
        {
            // TODO: validate input

            return UserRepository.GetAll()
                .Include(u => u.Roles)
                .SingleOrDefault(u => u.Username == username);
        }

        public virtual User FindByUsernameAndPassword(string username, string password)
        {
            // TODO: validate input

            var user = FindByUsername(username);

            if (user == null)
            {
                return null;
            }

            if (!Crypto.ValidateSaltedHash(user.HashedPassword, password, user.PasswordHashAlgorithm))
            {
                return null;
            }

            return user;
        }

        public virtual User FindByUsernameOrEmailAddressAndPassword(string usernameOrEmail, string password)
        {
            // TODO: validate input
            var user = FindByUsername(usernameOrEmail)
                       ?? FindByEmailAddress(usernameOrEmail);
                       
            if (user == null)
            {
                return ldapService.AutoEnroll(usernameOrEmail, password);
            }
            if (user.PasswordHashAlgorithm.Equals(Constants.LDAPHashAlgorithmId, StringComparison.OrdinalIgnoreCase))
            {
                if (ldapService.ValidateUser(usernameOrEmail, password))
                    return user;
                else
                    return null;
            }else{
                if (!Crypto.ValidateSaltedHash(user.HashedPassword, password, user.PasswordHashAlgorithm))
                {
                    return null;
                }
                else if (!user.PasswordHashAlgorithm.Equals(Constants.PBKDF2HashAlgorithmId, StringComparison.OrdinalIgnoreCase))
                {
                    // If the user can be authenticated and they are using an older password algorithm, migrate them to the current one.
                    ChangePasswordInternal(user, password);
                    UserRepository.CommitChanges();
                }
            }

            return user;
        }

        public string GenerateApiKey(string username)
        {
            var user = FindByUsername(username);
            if (user == null)
            {
                return null;
            }

            var newApiKey = Guid.NewGuid();
            user.ApiKey = newApiKey;
            UserRepository.CommitChanges();
            return newApiKey.ToString();
        }

        public bool ChangePassword(string username, string oldPassword, string newPassword)
        {
            // Review: If the old password is hashed using something other than PBKDF2, we end up making an extra db call that changes the old hash password.
            // This operation is rare enough that I'm not inclined to change it.
            var user = FindByUsernameAndPassword(username, oldPassword);
            if (user == null)
            {
                return false;
            }

            ChangePasswordInternal(user, newPassword);
            UserRepository.CommitChanges();
            return true;
        }

        public bool ConfirmEmailAddress(User user, string token)
        {
            if (user == null)
            {
                throw new ArgumentNullException("user");
            }

            if (String.IsNullOrEmpty(token))
            {
                throw new ArgumentNullException("token");
            }

            if (user.EmailConfirmationToken != token)
            {
                return false;
            }
            user.ConfirmEmailAddress();
            //added by fwang5: if use a same email register many times ,once activation ,all other records need clear username,token and unconfirmedEmail 
            IQueryable<User> list = FindByUnconfirmedEmailAddressList(user.EmailAddress, token);
            foreach (User tmpUser in list)
            {
                //clear invalid register user
                tmpUser.Username = tmpUser.EmailConfirmationToken;
                tmpUser.EmailConfirmationToken = null;
                tmpUser.UnconfirmedEmailAddress = null;
            }

            UserRepository.CommitChanges();
            return true;
        }

    

        public User GeneratePasswordResetToken(string usernameOrEmail, int tokenExpirationMinutes)
        {
            if (String.IsNullOrEmpty(usernameOrEmail))
            {
                throw new ArgumentNullException("usernameOrEmail");
            }
            if (tokenExpirationMinutes < 1)
            {
                throw new ArgumentException(
                    "Token expiration should give the user at least a minute to change their password", "tokenExpirationMinutes");
            }

            var user = FindByEmailAddress(usernameOrEmail);
            if (user == null)
            {
                return null;
            }

            if (!user.Confirmed)
            {
                throw new InvalidOperationException(Strings.UserIsNotYetConfirmed);
            }

            if (!String.IsNullOrEmpty(user.PasswordResetToken) && !user.PasswordResetTokenExpirationDate.IsInThePast())
            {
                return user;
            }

            user.PasswordResetToken = Crypto.GenerateToken();
            user.PasswordResetTokenExpirationDate = DateTime.UtcNow.AddMinutes(tokenExpirationMinutes);

            UserRepository.CommitChanges();
            return user;
        }

        public bool ResetPasswordWithToken(string username, string token, string newPassword)
        {
            if (String.IsNullOrEmpty(newPassword))
            {
                throw new ArgumentNullException("newPassword");
            }

            var user = (from u in UserRepository.GetAll()
                        where u.Username == username
                        select u).FirstOrDefault();

            if (user != null && user.PasswordResetToken == token && !user.PasswordResetTokenExpirationDate.IsInThePast())
            {
                if (!user.Confirmed)
                {
                    throw new InvalidOperationException(Strings.UserIsNotYetConfirmed);
                }

                ChangePasswordInternal(user, newPassword);
                user.PasswordResetToken = null;
                user.PasswordResetTokenExpirationDate = null;
                UserRepository.CommitChanges();
                return true;
            }

            return false;
        }

        private void ChangePasswordInternal(User user, string newPassword)
        {
            var hashedPassword = Crypto.GenerateSaltedHash(newPassword, Constants.PBKDF2HashAlgorithmId);
            user.PasswordHashAlgorithm = Constants.PBKDF2HashAlgorithmId;
            user.HashedPassword = hashedPassword;
        }
    }
}