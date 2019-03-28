module Feedback
  CONTAINER_NAME = "Feedback (Virtual)"
  SAMPLE_TYPE_NAME = "Operation Feedback"
  
  # This method will prompt the technician to write feedback for the operations
  # that they complete on each job. This feedback will be associated to an item
  # that represents each operation type.
  def get_protocol_feedback
    
    # Gets feedback from the user
    if debug
      feedback = "testing for job id"
    else
      feedback = ask_for_feedback
    end
    
    if(!feedback.blank?)
      associate_feedback feedback
    end
    
    if debug
      print_association
    end
    
  end
  
  # Associates the feedback entered by the lab technician to the OperationType of the protocol
  # that uses this library.
  #
  # @param [String] the feedback entered by the lab technician.
  def associate_feedback feedback
    operation = OperationType.find(operation_type.id)
    feedback = feedback + "- job #{jid}"
  
    feedback_array = []
    if(!operation.get(:feedback).nil?)
      feedback_array = operation.get(:feedback)
    end
    feedback_array.push(feedback)
    operation.associate :feedback, feedback_array
  end
  
  # Debugging method that prints all associations
  def print_association
    operation = OperationType.find(operation_type.id)
    feedback_array = operation.get(:feedback)
    if feedback_array
      show do
        title "This is printing because debug is on"
        note "#{feedback_array}"
      end
    end
  end
  
  # Returns the feedback entered by a lab technician.
  #
  # @return [Hash] the information returned by the feedback show block
  def ask_for_feedback
    feedback = show do
      title "We want your feedback"
      
      note "Notice anything weird with this protocol? Tell us below!"
      
      get "text", var: "feedback_user", label: "Enter your feedback here", default: ""
    end
    feedback[:feedback_user] # return
  end

end