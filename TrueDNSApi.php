<?php
/**
 * Description of DNSApi
 *
 * @author Kevin van Zonneveld
 * @copyright 2009 Kevin van Zonneveld (http://kevin.vanzonneveld.net)
 *
 */
class TrueDNSApi {
	protected $_options = array(
		'username' => '',
		'password' => '',
		'service' => 'https://www.truecare.nl/xml_engine.php',
		'hash' => '',
		'verifySSL' => false,
		'dryRun' => false,
	);

	protected $_records = array();

	public function  __construct($options) {
        // Merge parent's possible options with own
        $parent        = get_parent_class($this);
        $parentVars    = get_class_vars($parent);
        $parentOptions = $parentVars['_options'];
		if (!empty($parentOptions)) {
	        $this->_options = array_merge($parentOptions, $this->_options);
		}

		// Set real options
		$this->_options = array_merge($this->_options, $options);
	}

	public function records_index($domainName) {
		// Return Cache
		if (!empty($this->_records[$domainName])) {
			return $this->_records[$domainName];
		}

		$params = func_get_args();
		$Req  = new TrueDNSApi_Request($this->_options, __FUNCTION__, array(
			'domain' => $domainName,
		));

		if ($Req->errors) {
			print_r($Req->errors);
			return false;
		}

		$Records = $Req->body->xpath('//RECORD');
		$records = array();
		foreach($Records as $Record) {
			foreach($Record->attributes() as $Attribute) {
				$records[(string)$Record['id']][$Attribute->getName()] = (string)$Attribute;
			}
			$records[(string)$Record['id']]['content'] = (string)$Record;
		}

		// Update Cache
		$this->_records = $records;

		return $records;
	}

	public function records_edit($domainName, $record_id, $data) {
		$allowedFields = array_flip(array(
			'content',
			'prio',
			'ttl',
		));

		$data = array_intersect_key($data, $allowedFields);

		$params = func_get_args();
		$Req  = new TrueDNSApi_Request($this->_options, __FUNCTION__, array(
			'domain' => $domainName,
			'record_id' => $record_id,
		)+$data);
		
		if ($Req->errors) {
			print_r($Req->errors);
			return false;
		}

		// Update Cache
		if (!empty($this->_records[$domainName][$record_id])) {
			$this->_records[$domainName][$record_id] = array_merge($this->_records[$domainName][$record_id], $data);
		}

		return true;
	}

	public function records_delete($domainName, $record_id) {

		$params = func_get_args();
		$Req  = new TrueDNSApi_Request($this->_options, __FUNCTION__, array(
			'domain' => $domainName,
			'record_id' => $record_id,
		));

		if ($Req->errors) {
			print_r($Req->errors);
			return false;
		}

		// Update Cache
		if (!empty($this->_records[$domainName][$record_id])) {
			unset($this->_records[$domainName][$record_id]);
		}

		return true;
	}

	public function records_add($domainName, $subDomain, $data) {
		$allowedFields = array_flip(array(
			'type',
			'content',
			'prio',
			'ttl',
		));

		$data = array_intersect_key($data, $allowedFields);

		if ($subDomain == '') {
			$fqdn = $domainName;
		} else {
			if (substr($subDomain, -1) == '.') {
				$fqdn     = $subDomain . ''. $domainName;
			} else {
				$fqdn     = $subDomain . '.'. $domainName;
			}
		}

		$data['name'] = $fqdn;

		$params = func_get_args();
		$Req  = new TrueDNSApi_Request($this->_options, __FUNCTION__, array(
			'domain' => $domainName,
		)+$data);

		if ($Req->errors) {
			print_r($Req->errors);
			return false;
		}

		if (empty($Req->body->DNS->RECORDS_ADD->RECORD_ID)) {
			echo 'No record_id found!';
			var_dump($Req);
			return false;
		} else {
			$record_id = (string)$Req->body->DNS->RECORDS_ADD->RECORD_ID;
		}
		
		// Update Cache
		if (!empty($this->_records[$domainName][$record_id])) {
			$this->_records[$domainName][$record_id] = $data;
		}
		
		return $record_id;
	}
}

class TrueDNSApi_Request {
	protected $_options = array();
	protected $_curl = null;

	public $errors = array();
	public $body = '';


	/**
	* CURL write callback
	*
	* @param resource &$curl CURL resource
	* @param string &$data Data
	* @return integer
	*/
	public function  __construct($options, $method = null, $params = null) {
		$this->_options = array_merge($this->_options, $options);

		if (!empty($method) && $params !==null) {
			$this->send($method, $params);
		}
	}

	public function formXML($method, $params) {
		// Create
		$Xml = new SimpleXMLElement('<XML></XML>');
		$Auth = $Xml->addChild('AUTH');
		$Auth->addChild('DEB_ID', $this->_options['username']);
		$Auth->addChild('PASSWORD', $this->_options['password']);
		
		$Action = $Xml->addChild('ACTION');
		$Action->addAttribute('scope', 'dns');
		$Action->addAttribute('type', $method);
		if ($this->_options['dryRun']) {
			$Action->addChild('DRYRUN', 'true');
		}
		foreach($params as $k=>$v) {
			$tag = strtoupper($k);
			$Action->addChild($tag, $v);
		}

		// Formatting
		$doc = new DOMDocument('1.0');
		$doc->preserveWhiteSpace = false;
		$doc->loadXML($Xml->asXML());
		$doc->formatOutput = true;

		return $doc->saveXML();
	}

	public function send($method, $params) {
		$this->errors = array();
		$this->body = '';

		$data = array(
			'xml' => $this->formXML($method, $params),
			'hash' => $this->_options['hash'],
		);	

		$this->_curl = curl_init();
		curl_setopt($this->_curl, CURLOPT_URL, $this->_options['service']);
		curl_setopt($this->_curl, CURLOPT_POST, 1);
		curl_setopt($this->_curl, CURLOPT_RETURNTRANSFER, 1);
		curl_setopt($this->_curl, CURLOPT_POSTFIELDS, $data);
		curl_setopt($this->_curl, CURLOPT_USERAGENT, 'TrueDNSApi/php');
		if ($this->_options['verifySSL']) {
			curl_setopt($this->_curl, CURLOPT_SSL_VERIFYHOST, 1);
			curl_setopt($this->_curl, CURLOPT_SSL_VERIFYHOST, 1);
		} else {
			curl_setopt($this->_curl, CURLOPT_SSL_VERIFYHOST, 1);
			curl_setopt($this->_curl, CURLOPT_SSL_VERIFYHOST, 1);
		}
		$this->body = curl_exec($this->_curl);
		if (curl_errno($this->_curl) > 0)  {
			$this->errors[] = 'Curl error: '. curl_error($this->_curl).' ('.curl_errno($this->_curl).')';
		}
		curl_close($this->_curl);

		$b = $this->body;
		if (false === ($this->body = simplexml_load_string($this->body))) {
			print_r($b);
		}

		$errors = $this->body->xpath('//ERROR');
		if (!empty($errors)) {
			foreach($errors as $error){
				$this->errors[] = 'Serverside error: '.(string)$error;
			}
			return false;
		}

		if (!count($this->errors)) {
			$this->errors = false;
			return true;
		}
	}
}
?>