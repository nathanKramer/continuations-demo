/**
 * Contrived example to Demonstrate asynchronous callouts from Visualforce using Continuations. A feature introduced in Spring 15'
 * @author Logan Moore
 */
public with sharing class AddBookController {
    
    // A template for building a Google Books REST API endpoint
    private static final String GOOGLE_BOOKS_ENDPOINT = 'https://www.googleapis.com/books/v1/volumes?q={0}';
    
    // Will be explained later
    private String isbnRequestLabel;
    //private String generalRequestLabel;
    
    // A term to search for, provided by the user
    public String searchText { get; set; }
    
    // Results of the search
    public transient GoogleBooksResult isbnSearchResult { get; private set; }
    //public transient GoogleBooksResult generalSearchResult { get; private set; }

    /**
     * Synchronous http callout in visualforce. The way we're most familiar with.
     *
     * Problems: - Limit of 10 long running http callouts ORG WIDE!!!
     *           - http.send() method is blocking.
     *           - Chained callouts happen in the same thread. Overall time limit applies.
     */
    public void synchronousSearch() {
        Http http = new Http();
        String endpoint = String.format(GOOGLE_BOOKS_ENDPOINT, new String[] {'isbn:'+searchText});
        
        // This is a blocking method call, which means we're spending time and resources waiting.
        HttpResponse response = http.send(isbnSearchRequest());
        
        // We read the response, update the controller state and either reload or rerender the page.
        if(response.getStatusCode() == 200) {
            isbnSearchResult = parseResponse(response.getBody());
            ApexPages.addMessage(new ApexPages.Message(ApexPages.Severity.CONFIRM,'Synchronous Response Received ' + Datetime.now()));
        }
        else {
            // sumting wong, wi too lo, bang ding au
            ApexPages.addMessage(new ApexPages.Message(ApexPages.Severity.ERROR,'Response: ' + response.getStatusCode() + response.getStatus()));
        }
    }
    
    public HttpRequest isbnSearchRequest() {
        return buildHttpRequest(String.format(GOOGLE_BOOKS_ENDPOINT, new String[] {'isbn:' + EncodingUtil.urlEncode(searchText, 'UTF-8')}));
    }
    
    public HttpRequest generalSearchRequest() {
        return buildHttpRequest(String.format(GOOGLE_BOOKS_ENDPOINT, new String[] {EncodingUtil.urlEncode(searchText, 'UTF-8')}));
        // Can cause error by not encoding the searchTerm if it has a space. 400 response.
    }
    
    /**
     * Builds an http request that's suitable for sending to google.
     *
     * Nothing to see here, move along, move along.
     */
    public HttpRequest buildHttpRequest(String endpoint) {
        
        // Google requires an X-Forwarded-For header with the original clients IP (sneaky google, sneaky).
        // We can figure this about by looking at the current page headers for the True-Client-IP or X-Salesforce-SIP.
        String clientIp = ApexPages.currentPage().getHeaders().get('True-Client-IP');
        if (clientIp == null) {
            clientIp = ApexPages.currentPage().getHeaders().get('X-Salesforce-SIP');
        }
        
        // Build the http request to Googles API. Most of us are used to this by now.
        HttpRequest request = new HttpRequest();
        request.setEndpoint(endpoint);
        request.setMethod('GET');
        request.setHeader('X-Forwarded-For', clientIp);
        
        return request;
    }
    
    /**
     * Turns the JSON response from Google, into a DataStructure we can work with.
     */
    public GoogleBooksResult parseResponse(String googleBooksResultJSON) {
        JSONParser parser = JSON.createParser(googleBooksResultJSON);
        return (GoogleBooksResult)parser.readValueAs(GoogleBooksResult.class);
    }
    
    /**
     * Kicks off a Continuation which takes care of the callout for us. The method ends before the continuation completes.
     * Advantages: - Unlimited callouts (doesn't incur the org wide 10 long running http callout limit)
     *             - up to 3 callouts can be requested in the same continuation
     *             - The 3 callouts happen in parallel, callback is called as soon as the longest callback is complete.
     *             - Can chain more continuations on the back of a callback
     * Disadvantages: - Only works from VF context.
     *                - up to 3 callouts can be requested in the same continuation
     *                - 1MB response size limit.
     */
    public Object asynchronousSearch() {
    
        // Creates a continuation with a 60 second timeout
        Continuation cont = new Continuation(60);
        
        // Tell the continuation to callback to us when the callout is finish on the handleCallback method
        cont.continuationMethod = 'handleCallback';
        
        // Add an http request to the continuation
        // Also, store the unique request label that gets generated. We'll need it later.
        this.isbnRequestLabel = cont.addHttpRequest(isbnSearchRequest());
        
        // you cand add two more callouts here and store their requestLabels in the controller state as well.
        //this.generalRequestLabel = cont.addHttpRequest(generalSearchRequest());
        
        // Add a page message to confirm the continuation was enqueued. But we won't actually see this message.
        ApexPages.addMessage(new ApexPages.Message(ApexPages.Severity.INFO,'Asynchronous Message Enqueued ' + Datetime.now()));
        
        // Return the continuation to tell VF that its waiting for a continuation.
        return cont;
        
       // The VF page will be blocked and will wait for the continuation to complete.
    }
    
    /**
     * Is called by the continuation server when the http callout is completed.
     * Can return: - A continuation to chain another continuation.
     *             - A PageReference to redirect to a new page (use page parameters to pass details of the continuation response)
     *             - null to rerender the page
     */
    public Object handleCallback() {
        
        // Handle the response the same way as synchronous call
        // EXCEPT we have to get the HttpResponse object using the label that we stored earlier
        isbnSearchResult = parseResponse(Continuation.getResponse(this.isbnRequestLabel).getBody());
        
        // Handle a second response using its own requestLabel
        //generalSearchResult = parseResponse(Continuation.getResponse(this.generalRequestLabel).getBody());
        
        // Inform us that the results were fetched asynchronously
        ApexPages.addMessage(new ApexPages.Message(ApexPages.Severity.CONFIRM,'Asynchronous Response Received ' + Datetime.now()));
        
        // Return null to re-render the VF page
        return null;
    }
    
    
    /***
    
    IN SUMMARY
    
    Pros:
    
    - Up to 3 http request can be made simultaneously in a single continuation
    - Up to 3 continuations can be changed
    - Each continuation gets 120 seconds to complete
    - 
    
    Cons: 
    
    - Controller view state is limited to 80kb, because super secret salesforce reasons.
    - 
    
    ***/
}