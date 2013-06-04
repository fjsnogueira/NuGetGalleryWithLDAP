using System.Collections.Generic;

namespace NuGetGallery
{
    public class AccountViewModel
    {
        public string UserType { get; set; }
        public string ApiKey { get; set; }
        public IEnumerable<string> CuratedFeeds { get; set; }
    }
}